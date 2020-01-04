%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_mod_events_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include("emqx_mqtt.hrl").
-include_lib("eunit/include/eunit.hrl").

all() -> emqx_ct:all(?MODULE).

init_per_suite(Config) ->
    emqx_ct_helpers:boot_modules(all),
    emqx_ct_helpers:start_apps([emqx]),
    %% Ensure all the modules unloaded.
    ok = emqx_modules:unload(),
    Config.

end_per_suite(_Config) ->
    emqx_ct_helpers:stop_apps([emqx]).

%% Test case for emqx_mod_events
t_mod_events(_) ->
    ok = emqx_mod_events:load([{qos, ?QOS_1}]),
    {ok, C1} = emqtt:start_link([{clientid, <<"monsys">>}]),
    {ok, _} = emqtt:connect(C1),
    {ok, _Props, [?QOS_1]} = emqtt:subscribe(C1, <<"$SYS/brokers/+/clients/#">>, qos1),
    %% Connected Presence
    {ok, C2} = emqtt:start_link([{clientid, <<"clientid">>},
                                 {username, <<"username">>}]),
    {ok, _} = emqtt:connect(C2),
    ok = recv_and_check_events(<<"clientid">>, <<"connected">>),
    %% Disconnected Presence
    ok = emqtt:disconnect(C2),
    ok = recv_and_check_events(<<"clientid">>, <<"disconnected">>),
    ok = emqtt:disconnect(C1),
    ok = emqx_mod_events:unload([{qos, ?QOS_1}]).

t_mod_events_reason(_) ->
    ?assertEqual(normal, emqx_mod_events:reason(normal)),
    ?assertEqual(discarded, emqx_mod_events:reason({shutdown, discarded})),
    ?assertEqual(tcp_error, emqx_mod_events:reason({tcp_error, einval})),
    ?assertEqual(internal_error, emqx_mod_events:reason(<<"unknown error">>)).

t_mod_hook_point(_) ->
    ?assertEqual('client.connected', emqx_mod_events:hook_point("client_connected")),
    ?assertEqual('client.disconnected', emqx_mod_events:hook_point("client_disconnected")),
    ?assertEqual('session.subscribed', emqx_mod_events:hook_point("session_subscribed")),
    ?assertEqual('session.unsubscribed', emqx_mod_events:hook_point("session_unsubscribed")),
    %?assertEqual('message.acked', emqx_mod_events:hook_point("message_acked")),
    %?assertEqual('message.dropped', emqx_mod_events:hook_point("message_dropped")),
    %?assertEqual('message.delivered', emqx_mod_events:hook_point("message_delivered")),
    ?assertError(unsupported_event, emqx_mod_events:hook_point("message_notexists")),
    ?assertError(invalid_event, emqx_mod_events:hook_point("notexists")).

t_mod_hook_fun(_) ->
    Funcs = emqx_mod_events:module_info(exports),
    [?assert(lists:keymember(emqx_mod_events:hook_fun(Event), 1, Funcs)) ||
     Event <- ["client_connected",
               "client_disconnected",
               "session_subscribed",
               "session_unsubscribed"
               %"message_acked",
               %"message_dropped",
               %"message.delivered"
              ]].

recv_and_check_events(ClientId, Presence) ->
    {ok, #{qos := ?QOS_1, topic := Topic, payload := Payload}} = receive_publish(100),
    ?assertMatch([<<"$SYS">>, <<"brokers">>, _Node, <<"clients">>, ClientId, Presence],
                 binary:split(Topic, <<"/">>, [global])),
    case Presence of
        <<"connected">> ->
            ?assertMatch(#{clientid := <<"clientid">>,
                           username := <<"username">>,
                           ipaddress := <<"127.0.0.1">>,
                           proto_name := <<"MQTT">>,
                           proto_ver := ?MQTT_PROTO_V4,
                           connack := ?RC_SUCCESS,
                           clean_start := true}, emqx_json:decode(Payload, [{labels, atom}, return_maps]));
        <<"disconnected">> ->
            ?assertMatch(#{clientid := <<"clientid">>,
                           username := <<"username">>,
                           reason := <<"normal">>}, emqx_json:decode(Payload, [{labels, atom}, return_maps]))
    end.

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

receive_publish(Timeout) ->
    receive
        {publish, Publish} -> {ok, Publish}
    after
        Timeout -> {error, timeout}
    end.