defmodule NodeServer do
  use GenServer

  def start_link(hexNumStr) do
    {:ok, pid} = GenServer.start_link(__MODULE__, hexNumStr, name: String.to_atom("N"<>hexNumStr))

    [{_, totalcount}] = :ets.lookup(:table,"Total Nodes")
    [{_, bitlist}] = :ets.lookup(:table,"Levels")
    first = String.at(hexNumStr, 0)

    if totalcount > 1 do
      bitlist = Map.put(bitlist, first, bitlist[first] -- [hexNumStr])
      {level, neighbours} = populateRT(hexNumStr, bitlist, first)
      buildroutingtable(level, neighbours, hexNumStr)
    end

    {:ok, pid}
  end

  def init(hexNumStr) do
    # IO.puts "Node N#{hexNumStr} has been started"

    id = hexNumStr

    [{_, idbits}] = :ets.lookup(:table,"Identifierbits")
    rt = NodeServer.createRT(idbits)
    bp = NodeServer.createBP(idbits)

    # rt after initialization
    rt = NodeServer.initializeRT(rt, hexNumStr)

    # current nodes in the tapestry mesh => allnodes
    [{_, allnodes}] = :ets.lookup(:table,"Tapestry Nodes")
    [{_, bitlist}] = :ets.lookup(:table,"Levels")

    first = String.at(hexNumStr, 0)

    bitlist = (if Map.has_key?(bitlist, first) do
      lst = bitlist[first]
      lst = lst ++ [hexNumStr]
      Map.put(bitlist, first, lst)
    else
      Map.put(bitlist, first, [hexNumStr])
    end)

    #insert new node to global list
    :ets.insert(:table,{"Tapestry Nodes", Map.put(allnodes,hexNumStr, {String.to_atom("N"<>hexNumStr), self()})})
    :ets.insert(:table,{"Levels", bitlist})
    :ets.update_counter(:table,"Total Nodes",{2,1})

    {:ok, %{ "id" => id, "rt" => rt, "bp" => bp} }
  end

  def populateRT(node, list, n) do
    if(Map.has_key?(list, n) and Map.fetch!(list, n) != []) do
      # IO.inspect list[n]
      findrootnodes(node, list[n])
    else
      #populateRT(node, list, modifylevel(n))
      [{_, allnodes}] = :ets.lookup(:table,"Tapestry Nodes")
      {0, Map.keys(allnodes)}
    end
  end

  def modifylevel(n) do
    pos = rem(String.to_integer(n, 16) + 1, 16)
    Integer.to_string(pos, 16)
  end

  def findrootnodes(localnode, listofnodes) do
    [{_, idbits}] = :ets.lookup(:table,"Identifierbits")
    _findrootnodes(localnode,listofnodes,[], idbits)
  end
  defp _findrootnodes(localnode, listofnodes, [], lvl) do
    {:ok, regex} = "^"<>String.slice(localnode, 0..lvl-1)<>"*" |> Regex.compile
    matchedlist = Enum.map(listofnodes,fn x -> if String.match?(x,regex) do x end end) |> Enum.filter(& &1)
    _findrootnodes(localnode, listofnodes,matchedlist, lvl-1)
  end
  defp _findrootnodes(_localnode, _listofnodes, list, lvl) do
    {lvl, list}
  end

  def buildroutingtable(level, neighbours, self) do
    # IO.inspect neighbours
    Enum.each(neighbours, fn x ->
      assignneighbours(x,level, self)
    end)
    if(level-1 >= 0) do
      neighbours = getdownlevelbackpointers(neighbours, level-1)
      buildroutingtable(level-1, neighbours, self)
    end
  end

  def assignneighbours(neigh,level, own) do
    GenServer.cast(converttonode(neigh), {:reflectmessage, neigh, level, own})
  end

  def handle_cast({:setroutingtable, self, level, node}, state) do
    newstate = state
    rt = newstate["rt"]
    pos = String.to_integer(String.at(node, level), 16)
    cur_node = rt[level][pos]
    # IO.inspect node
    # IO.inspect pos
    # IO.inspect rt
    newstate = (
    if cur_node == nil do
      new_rt = Map.put(rt, level, Map.put(rt[level], pos, node))
      GenServer.cast(converttonode(node), {:updatebackpointer, self, level})
      Map.put(newstate, "rt", new_rt)
    else
      closer_node = getclosernode(self, node, cur_node)
      new_rt = Map.put(rt, level, Map.put(rt[level], pos, closer_node))
      if(closer_node != cur_node) do
        GenServer.cast(converttonode(node), {:updatebackpointer, self, level})
        GenServer.cast(converttonode(cur_node), {:removebp, level, self})
      end
      Map.put(newstate, "rt", new_rt)
    end)
    {:noreply, newstate}
  end

  def handle_cast({:reflectmessage, self, level, node}, state) do
    newstate = state
    rt = newstate["rt"]
    pos = String.to_integer(String.at(node, level), 16)
    cur_node = rt[level][pos]

    newstate = (
    if cur_node == nil do
      new_rt = Map.put(rt, level, Map.put(rt[level], pos, node))
      GenServer.cast(converttonode(node), {:updatebackpointer, self, level})
      Map.put(newstate, "rt", new_rt)
    else
      closer_node = getclosernode(self, node, cur_node)
      new_rt = Map.put(rt, level, Map.put(rt[level], pos, closer_node))
      if(closer_node != cur_node) do
        GenServer.cast(converttonode(node), {:updatebackpointer, self, level})
        GenServer.cast(converttonode(cur_node), {:removebp, level, self})
      end
      Map.put(newstate, "rt", new_rt)
    end)
    GenServer.cast(converttonode(node), {:setroutingtable, node, level, self})
    {:noreply, newstate}
  end

  def converttonode(node) do
    String.to_atom("N"<>node)
  end

  def getclosernode(self, node, cur_node) do
    dec_self = String.to_integer(self, 16)
    dec_node = String.to_integer(node, 16)
    dec_cur_node = String.to_integer(cur_node, 16)
    if abs(dec_self - dec_node) < abs(dec_self - dec_cur_node) do
      node
    else
      cur_node
    end
  end

  def handle_cast({:updatebackpointer, node, level}, state) do
    bp = state["bp"]
    new_bp = Map.put(bp, level, bp[level] ++ [node])
    {:noreply, Map.put(state, "bp", new_bp)}
  end

  def getdownlevelbackpointers(neighbours, level) do
    neighbourlist = Enum.map(neighbours, fn x -> getbackpointers(x, level) end)
    Enum.uniq(List.flatten(neighbourlist))
  end

  def getbackpointers(node, level) do
    state= GenServer.call(converttonode(node), {:getstatus})
    bp = state["bp"]
    bp[level]
  end

  def handle_cast({:removebp, level, node}, state) do
    bp = state["bp"]
    # IO.inspect node
    # IO.inspect state["id"]
    # IO.inspect level
    new_bp = Map.put(bp, level, bp[level] -- [node])
    {:noreply, Map.put(state, "bp", new_bp)}
  end

  def getnodeStatus(node) do
    GenServer.call(node, {:getstatus})
  end

  def handle_call({:getstatus}, _from, status) do
    {:reply, status, status}
  end

  def initializeRT(rt, hexNumStr) do
    [{_, noofbits}] = :ets.lookup(:table,"Identifierbits")
    nodevalue = hexNumStr
    hexbits = String.graphemes(nodevalue)
    _initRTlevels(rt, nodevalue, hexbits, 0, noofbits)
  end

  defp _initRTlevels(rt, nodevalue, list, count, noofbits) when count == noofbits-1 do
    # getting the last bit
    [lastval] = list

    # identifying the position of the last bit
    pos = NodeServer.valueToPosition(lastval)

    # obtaining updated last level
    lvllast = Map.put(rt[count], pos, nodevalue)

    # returning initalized RT
    Map.put(rt, count, lvllast)
  end

  defp _initRTlevels(rt, nodevalue, list, count, noofbits) do
    [head | tail] = list

    # identifying the position in level = count of the RT
    pos = NodeServer.valueToPosition(head)

    # obtaining updated level = count of the RT
    lvl = Map.put(rt[count], pos, nodevalue)

    # updated RT
    Map.put(rt, count, lvl) |> _initRTlevels(nodevalue, tail, count+1, noofbits)
  end

  def postionToValue(position) do
    case position do
      0 -> "0"
      1 -> "1"
      2 -> "2"
      3 -> "3"
      4 -> "4"
      5 -> "5"
      6 -> "6"
      7 -> "7"
      8 -> "8"
      9 -> "9"
      10 -> "A"
      11 -> "B"
      12 -> "C"
      13 -> "D"
      14 -> "E"
      15 -> "F"
    end
  end
  def valueToPosition(value) do
    case value do
      "0" -> 0
      "1" -> 1
      "2" -> 2
      "3" -> 3
      "4" -> 4
      "5" -> 5
      "6" -> 6
      "7" -> 7
      "8" -> 8
      "9" -> 9
      "A" -> 10
      "B" -> 11
      "C" -> 12
      "D" -> 13
      "E" -> 14
      "F" -> 15
    end
  end

  # function to convert 8 bit hexdecimal  to decimal
  def hex2int(hexStr) do
    hexbits = String.graphemes(hexStr)
    _hex2int(hexbits, 0 , 0)
  end
  defp _hex2int(list, total, 7) do
    [hexbit] = list
    total + valueToPosition(hexbit)
  end
  defp _hex2int(list, total, count) do
    [head | tail] = list
    multfactor = :math.pow(16,7 - count) |> round
    total = total + valueToPosition(head) * multfactor
    _hex2int(tail,total,count+1)
  end

  # To create RT and BP tables dynamically based on the no of identifier bits
  def createRT(noOfBits) do
    value = %{0 => nil,1 => nil,2 => nil,3 => nil,4 => nil,5 => nil,6 => nil,7 => nil,8 => nil,9 => nil,10 => nil,11 => nil,12 => nil,13 => nil,14 => nil,15 => nil}
    Enum.reduce(0..noOfBits-1, %{}, fn x,acc -> Map.put(acc, x , value) end)
  end

  def createBP(noOfBits) do
    Enum.reduce(0..noOfBits-1, %{}, fn x,acc -> Map.put(acc, x , []) end)
  end

  def sendrequest(source, deslist) do
    GenServer.cast(source, {:sendrequest, source, deslist})
  end

  def handle_cast({:sendrequest, source, deslist}, state) do
    Enum.each(deslist, fn des ->
      Process.send_after(source, {:sendmsg, source, des, 0}, 1000)
    end)
    {:noreply, state}
  end

  def handle_info({:sendmsg, source, destination, no_hops}, state) do
    # IO.puts "Diff is  at #{System.os_time(:millisecond) - starttime}"
    if(source == converttonode(destination)) do
      Tapestry.sendhop(no_hops)
    else
      pos = String.to_integer(String.at(destination, no_hops), 16)
      rt = state["rt"]
      new_source = rt[no_hops][pos]
      if new_source == nil do
        Tapestry.sendhop(no_hops)
      else
        new_source = converttonode(new_source)
        Process.send_after(new_source, {:sendmsg, new_source, destination, no_hops+1}, 0)
      end
    end
    {:noreply, state}
  end
end

