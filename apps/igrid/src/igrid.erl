-module(igrid).
-behaviour(gen_server).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% Local Function Exports
%% ------------------------------------------------------------------

-export([reserve/0,info/0]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_) ->
  Serv = ets:new(igridtable,[named_table,set]),
  State = { Serv },
  {ok, State}.

handle_call({enter, ClientTuple}, _From, State) ->
  {Serv, ClientSlots} = State,
  {Response, ClientId, NewSlots} = slot:reserve(ClientSlots, ClientTuple),
  {reply, {Response, ClientId}, {Serv, NewSlots}};
handle_call(info, _From, State) ->
  {reply, {ok, State}, State};
handle_call({release, ClientTuple}, _From, State) ->
  {Serv, ClientSlots} = State,
  {Response, NewSlots} = slot:release(ClientSlots, ClientTuple),
  NewState = {Serv, NewSlots},
  {reply, {Response, NewState}, NewState};
handle_call(_, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
%%

reserve() ->
  gen_server:call(?MODULE, {reserve}).

info() ->
  gen_server:call(?MODULE, {info}).

initialize_services(Port) ->
  process_flag(trap_exit, true),
  {ok, Socket} = gen_udp:open(Port, [binary, {active, false}, {recbuf, 65536}, {sndbuf, 65536}, {buffer, 65536}, {read_packets, 16000}]),
  io:format("mori starting.  Socket:~p~n",[Socket]),
  ets:new(udp_clients, [set, named_table, public]),
  ets:insert(udp_clients, { packets_seen, 0 }),
  %Heartbeat = spawn(fun() -> heartbeat(Socket) end),
  %link(Heartbeat),
  socket_loop(Socket).

socket_loop(Socket) ->
  inet:setopts(Socket, [{active, once}]),
  receive
    {udp, Socket, Host, Port, Bin} ->
      case ets:lookup(udp_clients, { Host, Port }) of
        [] -> 
          % new client
          Pid = mori_client:start({Socket, Host, Port}),
          ets:insert(udp_clients, { { Host, Port }, Pid }),
          Pid ! {cmd, Bin};
        [{{Host, Port}, Pid}] ->
          Pid ! {cmd, Bin}
      end;
    {'EXIT', FromPid, Reason} ->
      case Reason of
        {shutdown, {Host, Port}} ->
            ets:delete(udp_clients, {Host, Port});
        _ ->
          io:format("unusual exit: ~p~n", [[FromPid, Reason]]),
          ok
      end
  end,
  socket_loop(Socket).