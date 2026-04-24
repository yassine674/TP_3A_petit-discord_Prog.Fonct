defmodule MiniDiscord.Salon do
  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, %{name: name, clients: [], historique: []},
      name: via(name))
  end

  def rejoindre(salon, pid), do: GenServer.call(via(salon), {:rejoindre, pid})
  def quitter(salon, pid),   do: GenServer.call(via(salon), {:quitter, pid})
  def broadcast(salon, msg), do: GenServer.cast(via(salon), {:broadcast, msg})

  def lister do
    Registry.select(MiniDiscord.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def init(state), do: {:ok, state}

  def handle_call({:rejoindre, pid}, _from, state) do
    Process.monitor(pid)
    # Envoyer l'historique au nouveau client
    Enum.each(state.historique, fn msg -> send(pid, {:message, msg}) end)
    new_state = %{state | clients: [pid | state.clients]}
    {:reply, :ok, new_state}
  end

  def handle_call({:quitter, pid}, _from, state) do
    new_state = %{state | clients: List.delete(state.clients, pid)}
    {:reply, :ok, new_state}
  end

  def handle_cast({:broadcast, msg}, state) do
    Enum.each(state.clients, fn pid -> send(pid, {:message, msg}) end)
    # Ajouter à l'historique, garder max 10 messages (Enum.take garde les N premiers)
    nouvel_historique =
      [msg | state.historique]
      |> Enum.take(10)
    {:noreply, %{state | historique: nouvel_historique}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    new_state = %{state | clients: List.delete(state.clients, pid)}
    {:noreply, new_state}
  end

  defp via(name), do: {:via, Registry, {MiniDiscord.Registry, name}}
end