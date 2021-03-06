$if -fieldregex'form'='^js$'$$header -filetype(js)$
var rootPath = '$value -rootpath$',
    app = angular.module('iService', ['ngSanitize', 'ngRoute', 'ui.date']),
    loggedIn = $json -loginloggedin$,
    canAgentLogin = $if -domainuser$true$else$false$endif$,
    messageList = {},
    agentList = {},
    agentsByID,
    nobody = null,
    agents,
    httpService,
    fetchParams,
    numberFormatOptions = {
        minimumIntegerDigits: 2,
        useGrouping: false
    };

iservice.ProcessLogin(loggedIn);

app.filter('formatInterval', function ()
{
    return function (wholeHours)
    {
        var hours,
            minutes;

        hours = Math.floor(wholeHours);
        minutes = (wholeHours - hours) * 60;

        return hours.toString() + ":" + minutes.toLocaleString("en", numberFormatOptions);
    };
});

function onDataFetched(data)
{
    agentsByID = {};
    agents = [];
    nobody = null;

    iservice.SanitizeHistoryRows(data.interactions);

    data.interactions.forEach(function (inter)
    {
        inter.hours = iservice.calculateWorkHours(inter.dateObj);
    });

    messageList.NewRows(data.interactions);

    data.interactions.forEach(incrementAgent);

    agents.forEach(function (ag)
    {
        ag.hours = iservice.calculateWorkHours(ag.oldestObj);
    });

    agentList.NewRows(agents);

    // TODO: Data should be refreshed using live socket connection
    setTimeout(fetchData, 15 * 1000); // Refresh the data every 15 seconds
}

function fetchData()
{
    return iservice.MessageSearch(httpService, fetchParams, 0, 1000, null, onDataFetched);
}

function incrementAgent(message)
{
    var id = message.assignedToID;

    if(id)
    {
        var agent = agentsByID[id];

        if(agent)
        {
            agent.num++;

            if(message.dateObj < agent.oldestObj)
            {
                agent.oldestObj = message.dateObj;
                agent.date = message.date;
            }

            return;
        }

        agent = { id: message.assignedToID, name: message.agentName, num: 1, oldest: message.date, oldestObj: message.dateObj };

        agentsByID[id] = agent;
        agents.push(agent);

        return;
    }

    message.assignedToID = 'none';

    if(nobody)
    {
        nobody.num++;

        if(message.dateObj < nobody.oldestObj)
        {
            nobody.oldestObj = message.dateObj;
            nobody.date = message.date;
        }

        return;
    }

    nobody = { id: 'none', name: 'Unassigned', num: 1, oldest: message.date, oldestObj: message.dateObj };

    agents.push(nobody);
}

function ControllerMessageQueueSuperviseByAgent($scope, $http, $timeout)
{
    $scope.tabs = [
      { name: 'My Queue', right: 'Tab.Top.MessageQueue', path: rootPath + 'f/messagequeue' },
      { name: 'Manage Msgs', right: 'Tab.MessageQueue.Supervise', path: rootPath + 'MessageQueue.aspx?mode=managemessages' },
      { name: 'Manage Chats', right: 'Tab.MessageQueue.SuperviseChat', path: rootPath + 'MessageQueue.aspx?mode=managechats' },
      { name: 'Search', right: 'Tab.MessageQueue.Search', path: rootPath + 'MessageQueue.aspx?mode=search' }
    ];

    $scope.currentTab = $scope.tabs[1];
    $scope.MainTabClass = function (tab) { return (tab == $scope.currentTab) ? 'active' : 'inactive'; };

    var statuses = [ $repeat -messagesearchfields(statuses)$ { id: '$value -Pjs -messagesearchfield(value)$', name: '$value -Pjs -messagesearchfield(name)$' } $if -more$,
                     $endif$$endrepeat$ ],
    unassigned,
    queued;

    for(var i = 0; i < statuses.length; i++)
    {
        var status = statuses[i];

        if(status.name == 'Queued') queued = status.id;

        if(status.name == 'Unassigned') unassigned = status.id;
    }

    var param = {
        groups:
          [{
              fields:
              [{ where: 'entire', fieldID: 'status', searchString: unassigned },
                { where: 'entire', fieldID: 'status', searchString: queued }]
          }]
    };

    $scope.agentList = agentList;

    InstallControllerSort(agentList, { column: 'num', ascend: false });

    $scope.messageList = messageList;

    InstallControllerSort(messageList, { column: 'dateObj', ascend: true });

    $scope.showFor = null;
    $scope.ShowMessage = function (value, index, array)
    {
        return $scope.showFor && value.assignedToID == $scope.showFor.id;
    }

    httpService = $http;
    fetchParams = param;

    $scope.SearchRunning = fetchData();

    $scope.SelectAgent = function (agent)
    {
        $scope.showFor = agent;
    }
}

// TODO: This controller is copied from form 53. We need to place it in a common script file
function ControllerFALogin($scope, $http)
{
    $scope.toggleLogin = iservice.loggedIn.isLoggedIn;

    $scope.reset = function (login)
    {
        if(login)
        {
            login.$pristine = true
            login.$valid = true
            $scope.toggleLogin = !$scope.toggleLogin
        }
    };

    $scope.Login = function ()
    {
        $scope.submitted = true;
        $scope.errors = [];
        if(!$scope.login.$invalid)
        {
            $scope.Loading = iservice.Login($http, $scope.emailAddress, $scope.password, function (data)
            {
                if(!data.loggedIn.isLoggedIn) { $scope.errors = ['The information you entered doesn\u0027t match our records. Please try again.']; return; }
                if(data.errors && data.errors.length) return;
                iservice.ProcessLogin(data.loggedIn);

                fetchData();
            });
        }
    }
    $scope.Logout = function ()
    {
        $scope.errors = [];
        $scope.Loading = iservice.Logout($http, function (data)
        {
            iservice.ProcessLogin(data.loggedIn);
        });
    }
}

var ControllerAgent = ControllerWithID('Agent'),
    ControllerMessage = ControllerWithID('Message');

$endif$
$if -fieldregex'form'='^$'$
<!DOCTYPE html>
<html xmlns:ng="http://angularjs.org" id="ng-app" ng-app="iService">
<head>
    $include -placeholder'common-head' -indent'  '$
    <link rel="stylesheet" href="//cdnjs.cloudflare.com/ajax/libs/foundation/6.1.1/foundation.min.css" />
    <link rel="stylesheet" href="$value -rootpath$css/webapp.messagequeue.css" />
    <link rel="stylesheet" href="$value -rootpath$f/$value -formid$?form=css" />
    <link rel="stylesheet" href="$value -rootpath$f/53?form=css" />
</head>
<body ng-controller="ControllerBody">
    <div ng-cloak class="page loginsection" ng-controller="ControllerFALogin">
        <div ng-show="iservice.loggedIn.isLoggedIn" class="login_container">
            <span class="loggedinuname"> Hello </span>{{ iservice.loggedIn.contactName }}
            <button id="logout" class="logoutbtn" ng-click="Logout()">Logout</button>
        </div>

        <form ng-show="!iservice.loggedIn.isLoggedIn" name="login" action="" method="POST" novalidate>
            <div class="login_container">
                <a href="javascript:void(0)" id="show_login" ng-click="toggleLogin = !toggleLogin">Login</a>
            </div>
            <div class="box_wrap" id="box_wrap" ng-hide="toggleLogin" ng-animate="'box_wrap'">
                <img width="16" height="12" title="" alt="" src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAYAAAEc4A0XAAAACXBIWXMAAAsTAAALEwEAmpwYAAAABGdBTUEAALGOfPtRkwAAACBjSFJNAAB6JQAAgIMAAPn/AACA6QAAdTAAAOpgAAA6mAAAF2+SX8VGAAABc0lEQVR42mL8//8/AwgABBATiHj1+s1/gABiAIncu3cvECCAQMTkl69e/wcIILAIVLQXJAAQQHABmFKAAGJhgAKQAUxMTAwAAYQwDQj+/ftXCRBAKFqQtHa9ePnq/6PHj/8DBBDcCBC4f//+BG4e3nwgBvP//P59GSCAGEE6gBLTgIKZDGjg65fPGgABhNUKqDW7QDRAADHC/IoMHj569J+TkwtkQgpAADGhSz6CSkLBKYAAQjEB5GoODk4GqBcZJMTFGAECCG7C48dP4JJgH/z5DaYBAogF6AN+FlbWD+wcHChW/f3zB0wDBBBWR+ICQMPqGBmZGtk52Bl+//4NMiQIIIBYiNTYy8zMXMTFzcPAyMgIFgMZAAS/AAIIrwtAMcPMzJLPwcnJgCUSQBQ7QACx4NA4mYWFJQcWpegAGkDLFBUVfwEEEHpamAYMsExcGhEGgANwGYgACCBQKLsC6UxWNrZAQhph4N/fvyDqCIgACDAAcxzWeG16dZIAAAAASUVORK5CYII=" class="login_arrow" />
                <div class="box">
                    <div class="clear"></div>
                    <div class="box_con">
                        <div ng-cloak ng-repeat="error in errors" class="error-messages">{{ error }} </div>
                        <div>

                            <span class="l">Login</span>
                            <span class="l_row control-group" ng-class="{true: 'error'}[submitted && login.username.$invalid]">
                                <input type="email" name="username" class="uname" placeholder="Email" ng-model="emailAddress" required>
                                <span class="validation_error" ng-show="submitted && login.username.$error.required">Email Required</span>
                                <span class="validation_error" ng-show="submitted && login.username.$error.email">Invalid email</span>
                            </span>
                            <span class="l_row control-group" ng-class="{true: 'error'}[submitted && login.password.$invalid]">
                                <input type="password" name="password" class="upassword" placeholder="Password" ng-model="password" required>
                                <span class="validation_error" ng-show="submitted && login.password.$error.required">Password Required</span>
                            </span>
                            <span class="l_btn_row">
                                <input type="submit" class="btn_okay" value="Login" ng-click="Login()" />
                                <input type="button" class="btn_cancel" value="Cancel" ng-click="reset(login)" />
                            </span>
                            <span class="box-title">
                                <a href="javascript:void(0)">Forgot Password</a>
                            </span>
                            <div grey-out ng-show="Loading()"></div>
                        </div>
                        <div class="clear"></div>
                    </div>
                </div>
            </div>
        </form>
    </div>
    <div class="clear"></div>
    <section ng-show="!iservice.loggedIn.isLoggedIn" class="main-tabbed-content common-tabs-container">
        <strong>Please login to view the messages</strong>
    </section>
    <div ng-cloak id="messagequeue" ng-controller="ControllerMessageQueueSuperviseByAgent" class="main-tabbed-content common-tabs-container" ng-show="HaveRight('Tab.Top.MessageQueue')">
        <div class="common-tabs" ng-cloak>
            <div ng-repeat="tab in tabs" ng-controller="ControllerTab" ng-show="HaveRight(tab.right)" class="tab" ng-class="MainTabClass(tab)"><a id="{{idPrefix}}link" href="{{tab.path}}">{{ tab.name }}</a></div>
        </div>
        <div ng-include="'superviseByAgentBody.html'"></div>
    </div>
    $include -placeholder'common-footer' -indent'  '$
    $include -placeholder'interaction-properties' -indent'  '$
    $include -placeholder'history-partials' -indent'  '$
    $include -placeholder'common-javascript' -indent'  '$
    <script type="text/javascript" src="$value -rootpath$js/iService.messagequeue.js?v=$value -version -urlencode$"></script>
    <script type="text/javascript" src="$value -rootpath$f/84"></script>
    <script type="text/javascript" src="$value -rootpath$f/$value -formid$?form=js"></script>
    <script src="$value -rootpath$js/iService.directive.js?v=$value -version -urlencode$"></script>
    <script type="text/ng-template" id="superviseByAgentBody.html">
        <h2>Count of open messages by agent.</h2>
        <table class="messages common-search-results hover stack">
            <thead>
                <tr>
                    <th class="column-name"><span class="nglink" ng-click="agentList.SortClick('name')">Agent Name</span><div class="sort-direction-indicator" ng-class="agentList.SortDirectionClass('name')"></div></th>
                    <th class="column-num"><span class="nglink" ng-click="agentList.SortClick('num')"># Messages Assigned</span><div class="sort-direction-indicator" ng-class="agentList.SortDirectionClass('num')"></div></th>
                    <th class="column-hours"><span class="nglink" ng-click="agentList.SortClick('hours')">Oldest Message Business Hours</span><div class="sort-direction-indicator" ng-class="agentList.SortDirectionClass('oldHours')"></div></th>
                </tr>
            </thead>
            <tbody class="agents">
                <tr ng-repeat="agent in agentList.rows" ng-class-even="'row-even'" ng-class-odd="'row-odd'" ng-class="{'row-selected': showFor === agent }" ng-controller="ControllerAgent">
                    <td class="column-name padded">{{ agent.name }}</td>
                    <td class="column-num padded"><span class="nglink" ng-click="SelectAgent(agent)">{{ agent.num }}</span></td>
                    <td class="column-hours padded">{{ agent.hours | formatInterval }}</td>
                </tr>
            </tbody>
        </table>
        <h2 ng-show="showFor">Messages for: {{showFor.name}}<br></h2>
        <table class="messages common-search-results hover stack" ng-show="showFor">
            <thead>
                <tr>
                    <th class="column-topic"><span class="nglink" ng-click="messageList.SortClick('topicName')">Topic Name</span><div class="sort-direction-indicator" ng-class="messageList.SortDirectionClass('topicName')"></div></th>
                    <th class="column-date"><span class="nglink" ng-click="messageList.SortClick('dateObj')">Message Date</span><div class="sort-direction-indicator" ng-class="messageList.SortDirectionClass('dateObj')"></div></th>
                    <th class="column-hours"><span class="nglink" ng-click="messageList.SortClick('hours')">Business Hours</span><div class="sort-direction-indicator" ng-class="messageList.SortDirectionClass('hours')"></div></th>
                </tr>
            </thead>
            <tbody class="agents">
                <tr ng-repeat="message in messageList.rows | filter: ShowMessage" ng-class-even="'row-even'" ng-class-odd="'row-odd'" ng-controller="ControllerMessage">
                    <td class="column-topic padded">{{ message.topicName }}</td>
                    <td class="column-date padded">{{ message.date }}</td>
                    <td class="column-hours padded">{{ message.hours | formatInterval }}</td>
                </tr>
            </tbody>
        </table>
    </script>
</body>
</html>
$endif$$if -fieldregex'form'='^css$'$$header -filetype(css)$
/* Foundation overrides */
tbody td,
tbody th,
tfoot td,
tfoot th,
thead td,
thead th
{
    padding: 0; /* Eliminate the big padding set by Foundation */
}
/* End of Foundation overrides*/

.common-search-results { width: 100%; table-layout: fixed; }
.common-search-results td { border: solid 1px #cacaca; border-top: none; }
.common-search-results th { border-bottom: solid 1px #cacaca; }
.common-search-results tr.row-even td { background-color: #e8e8e8; }
.common-search-results tr.row-odd td { background-color: #fff; }
.common-search-results tr.row-selected td { background-color: #f0fff0; }
$endif$
