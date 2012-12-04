%%%-------------------------------------------------------------------
%%% @copyright (C) 2012, VoIP INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(wh_media_file).

-export([get_uri/2]).
-export([maybe_prepare_proxy/1]).

-include("whistle_media.hrl").

-spec get_uri/2 :: ([ne_binary(),...] | ne_binary(), wh_json:object()) -> {'ok', ne_binary()} |
                                                                          {'error', 'not_found'} |
                                                                          {'error', 'no_data'} |
                                                                          {'error', 'no_stream_strategy'}.
get_uri(Media, JObj) when is_binary(Media) ->
    Paths = [Path 
             || Path <- binary:split(Media, <<"/">>, [global, trim])
                    ,(not wh_util:is_empty(Path))
            ],
    get_uri(Paths, JObj);
get_uri(Paths, JObj) ->        
    case find_attachment(Paths) of
        {error, _}=E -> E;
        {ok, {Db, Id, Attachment}} ->
            maybe_local_haproxy_uri(JObj, Db, Id, Attachment)
    end.            

-spec maybe_prepare_proxy/1 :: (ne_binary()) -> 'ok' | 'error'.            
maybe_prepare_proxy(URI) ->
    case wh_util:to_binary(props:get_value(path, uri_parser:parse(wh_util:to_list(URI), []), <<>>)) of
        <<"/single/", Rest/binary>> -> prepare_proxy(binary:split(Rest, <<"/">>, [global, trim]));
        <<"/continuous/", Rest/binary>> -> prepare_proxy(binary:split(Rest, <<"/">>, [global, trim]));
        _Else -> ok
    end.    

-spec prepare_proxy/1 :: ([ne_binary(),...]) -> 'ok' | 'error'.
prepare_proxy([Db, Id, Attachment]) ->
    case wh_media_cache_sup:find_file_server(Db, Id, Attachment) =:= {error, no_file_server} of
        true -> start_media_file_cache(Db, Id, Attachment);
        false -> lager:debug("existing file server for ~s/~s/~s", [Db, Id, Attachment])
    end.  
             
-spec start_media_file_cache/3 :: (ne_binary(), ne_binary(), ne_binary()) -> 'ok'.
start_media_file_cache(Db, Id, Attachment) ->
    {ok, _FileServer} = wh_media_cache_sup:start_file_server(Db, Id, Attachment),
    lager:debug("file server at ~p for ~s/~s/~s", [_FileServer, Db, Id, Attachment]).

-spec find_attachment/1 :: ([ne_binary(),...] | ne_binary()) -> {'ok', {ne_binary(), ne_binary(), ne_binary()}} |
                                                                {'error', 'not_found'}.
find_attachment([Id]) ->
    find_attachment([?MEDIA_DB, Id]);
find_attachment([Db, Id]) ->
    find_attachment([Db, Id, first]);
find_attachment([Db, Id, first]) ->
    maybe_find_attachment(Db, Id);
find_attachment([Db = ?MEDIA_DB, Id, Attachment]) ->
    {ok, {Db, Id, Attachment}};
find_attachment([Db, Id, Attachment]) ->
    AccountDb =  wh_util:format_account_id(Db, encoded),
    {ok, {AccountDb, Id, Attachment}};
find_attachment(Id) when not is_list(Id) ->
    find_attachment([Id]).

-spec maybe_find_attachment/2 :: (ne_binary(), ne_binary()) -> {'ok', {ne_binary(), ne_binary(), ne_binary()}} |
                                                               {'error', 'not_found'}.
-spec maybe_find_attachment/3 :: (wh_json:object(), ne_binary(), ne_binary()) -> {'ok', {ne_binary(), ne_binary(), ne_binary()}} |
                                                                                 {'error', 'not_found'} |                  
                                                                                 {'error', 'no_data'}.

maybe_find_attachment(?MEDIA_DB = Db, Id) ->
     {ok, {Db, Id, <<Id/binary, ".wav">>}};
maybe_find_attachment(Db, Id) -> 
    AccountDb = wh_util:format_account_id(Db, encoded),
    case couch_mgr:open_doc(AccountDb, Id) of
        {error, _R} ->
            lager:debug("unable to open media doc ~s in ~s: ~p", [Id, Db, _R]),
            {error, not_found};
        {ok, JObj} -> 
            maybe_find_attachment(JObj, AccountDb, Id)
    end.

maybe_find_attachment(JObj, Db, Id) ->
    lager:debug("trying to find first attachment on doc ~s in db ~s", [Id, Db]),
    case wh_json:get_value(<<"_attachments">>, JObj, []) of
        [] ->
            lager:debug("media doc ~s in ~s has no attachments", [Id, Db]),
            {error, no_data};
        Attachments ->
            {Attachment, _} = hd(wh_json:to_proplist(Attachments)),
            lager:debug("found first attachment ~s on ~s in ~s", [Attachment, Id, Db]),
            {ok, {Db, Id, Attachment}}
    end.

-spec maybe_local_haproxy_uri/4 :: (wh_json:object(), ne_binary(), ne_binary(), ne_binary()) -> {'ok', ne_binary()} |
                                                                                                {'error', 'no_stream_strategy'}.
maybe_local_haproxy_uri(JObj, Db, Id, Attachment) ->
    case whapps_config:get_is_true(?CONFIG_CAT, <<"use_bigcouch_direct">>, false) of
        false -> maybe_media_manager_proxy_uri(JObj, Db, Id, Attachment);
        true ->
            DefaultHost = case couch_mgr:get_host() of
                              "localhost" -> wh_network_utils:get_hostname();
                              Else -> Else
                          end,
            Host = whapps_config:get_binary(?CONFIG_CAT, <<"bigcouch_host">>, wh_util:to_binary(DefaultHost)),
            Port = whapps_config:get_binary(?CONFIG_CAT, <<"bigcouch_port">>, couch_mgr:get_port()),
            Permissions = case wh_media_util:convert_stream_type(wh_json:get_value(<<"Stream-Type">>, JObj)) 
                              =:= <<"store">> 
                          of
                              true -> direct_store;
                              false -> direct_playback
                          end,
            {ok, <<(wh_media_util:base_url(Host, Port, Permissions))/binary
                   ,Db/binary, "/", Id/binary, "/", Attachment/binary>>}
    end.

-spec maybe_media_manager_proxy_uri/4 :: (wh_json:object(), ne_binary(), ne_binary(), ne_binary()) -> {'ok', ne_binary()} |
                                                                                                      {'error', 'no_stream_strategy'}.
maybe_media_manager_proxy_uri(JObj, Db, Id, Attachment) ->
    case whapps_config:get_is_true(?CONFIG_CAT, <<"use_media_proxy">>, true) of
        false -> 
            lager:warning("unable to build URL for media ~s ~s ~s", [Db, Id, Attachment]),
            {error, no_stream_strategy}; 
        true ->
            Host = wh_network_utils:get_hostname(),
            Port = whapps_config:get_binary(?CONFIG_CAT, <<"proxy_port">>, 24517),
            StreamType = wh_media_util:convert_stream_type(wh_json:get_value(<<"Stream-Type">>, JObj)),            
            Permissions = case StreamType =:= <<"store">> of
                              true -> proxy_store;
                              false -> proxy_playback
                          end,
            {ok, <<(wh_media_util:base_url(Host, Port, Permissions))/binary, StreamType/binary
                   ,"/", Db/binary, "/", Id/binary, "/", Attachment/binary>>}
    end.
