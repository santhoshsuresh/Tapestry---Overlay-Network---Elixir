defmodule NodeSupervisor do
  use Supervisor

  def start_link(numOfNodes) do
    Supervisor.start_link(__MODULE__, numOfNodes)
  end

  def init(numOfNodes) do
    # global list of nodes
    table = :ets.new(:table, [:named_table,:public])
    :ets.insert(table,{"Tapestry Nodes",%{}})
    :ets.insert(table,{"Total Nodes",0})
    :ets.insert(table,{"Levels",%{}})
    :ets.insert(table,{"Identifierbits", 0})

    # list containing a total of N (numOfNodes) random hexadecimal string values
    list = NodeSupervisor.hashfunction(numOfNodes)

    child_nodes = Enum.map(Enum.uniq(list), fn n -> worker(NodeServer, [n], [id: n, restart: :temporary]) end)
    supervise(child_nodes, strategy: :one_for_one)
  end

  def convertToHex(number) do
    Integer.to_string(number, 16)
  end

  def hashfunction(numOfNodes) do
    level = findlevel(numOfNodes)
    # IO.inspect "level #{level}"
    level = (if(numOfNodes > (:math.pow(16,level) - :math.pow(16,level-1))) do
      level + 1
    else
      level
    end)

    :ets.insert(:table,{"Identifierbits", level})

    maxNodeValue = (:math.pow(16,level)-1) |> round
    minNodeValue = :math.pow(16,level-1) |> round
    child_list = createchildlist(%{}, minNodeValue, maxNodeValue, 0, numOfNodes)
    Enum.map(child_list, fn x -> NodeSupervisor.convertToHex(x) end)
  end

  def createchildlist(nodelist, _min, _max, count, total) when count == total do
    Map.keys(nodelist)
  end
  def createchildlist(nodelist, min, max, count, total) when count < total do
    node = Enum.random(min..max)
    if(Map.has_key?(nodelist, node)) do
      createchildlist(nodelist, min, max, count, total)
    else
      createchildlist(Map.put(nodelist, node, node), min, max, count+1, total)
    end
  end

  def findlevel(num, count \\ 0) do
    if(ceil(num/16) > 1.0) do
      findlevel(ceil(num/16), count+1)
    else
      count+1
    end
  end

  def sendmessage msgcount do
    [{_, allnodes}] = :ets.lookup(:table,"Tapestry Nodes")
    nodes = Map.keys(allnodes)
    Enum.each(nodes, fn node ->
      lst = Enum.take_random(nodes -- [node], msgcount)
      NodeServer.sendrequest(String.to_atom("N"<>node), lst)
    end)
  end

  def waitfunc(startTime, nodecount, req) do
    endTime = System.os_time(:millisecond)
    time = endTime - startTime
    [_hop, count] = Tapestry.gethop()
    if((count < (nodecount*req)) or time<=(1000*req)) do
      waitfunc(startTime, nodecount, req)
    end
  end

end
