defmodule Tapestry do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, 0, name: :monitor)
  end

  def init hop do
    {:ok, [hop, 0]}
  end

  def sendhop no_hops do
    GenServer.cast(:monitor, {:sendhop, no_hops})
  end

  def handle_cast({:sendhop, no_hops}, state) do
    [old_value,count] = state
    newvalue = (
      if old_value < no_hops do
        no_hops
      else
        old_value
      end)
    {:noreply, [newvalue, count+1]}
  end

  def gethop do
    GenServer.call(:monitor, {:readhop})
  end

  def handle_call({:readhop}, _from, state) do
    {:reply, state, state}
  end
end
