%%%-------------------------------------------------------------------
%%% @copyright (C) 2018, 2600Hz
%%% @doc
%%%
%%% @end
%%% @contributors
%%%-------------------------------------------------------------------
-module(doodle_app).

-behaviour(application).

-include("doodle.hrl").
-define(ACCOUNT_CRAWLER_BINDING, <<"tasks.account_crawler">>).

-export([start/2, stop/1]).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Implement the application start behaviour
%% @end
%%--------------------------------------------------------------------
-spec start(application:start_type(), any()) -> startapp_ret().
start(_Type, _Args) ->
    _ = declare_exchanges(),
    case kapps_config:get_json(?CONFIG_CAT, <<"reschedule">>) =:= undefined
        andalso kz_json:load_fixture_from_file(?APP, <<"fixtures">>, <<"reschedule.json">>)
    of
        false -> ok;
        {'error', Err} -> lager:error("default sms is undefined and cannot read default from file: ~p", [Err]);
        JObj -> kapps_config:set(?CONFIG_CAT, <<"reschedule">>, JObj)
    end,
    lager:debug("Start listening for tasks.account_crawler trigger"),
    _ = kazoo_bindings:bind(?ACCOUNT_CRAWLER_BINDING,
                            'doodle_maintenance',
                            'start_check_sms_by_account'),
    doodle_sup:start_link().

%%--------------------------------------------------------------------
%% @public
%% @doc Implement the application stop behaviour
%%--------------------------------------------------------------------
-spec stop(any()) -> any().
stop(_State) ->
    _ = kazoo_bindings:unbind(?ACCOUNT_CRAWLER_BINDING,
                              'doodle_maintenance',
                              'start_check_sms_by_account'),
    'ok'.

-spec declare_exchanges() -> 'ok'.
declare_exchanges() ->
    _ = kapi_notifications:declare_exchanges(),
    _ = kapi_route:declare_exchanges(),
    _ = kapi_sms:declare_exchanges(),
    _ = kapi_registration:declare_exchanges(),
    kapi_self:declare_exchanges().
