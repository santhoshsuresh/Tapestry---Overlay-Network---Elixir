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
    # IO.puts "Node :N#{hexNumStr} has been started"
    {:ok, pid}
  end

  def init(hexNumStr) do
    # IO.puts "Node N#{hexNumStr} has been started"

    id = hexNumStr

    [{_, idbits}] = :ets.lookup(:table,"Identifierbits")
    rt = NodeServer.createRT(idbits)
    brt = NodeServer.createBRT(idbits)
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

    {:ok, %{ "id" => id, "rt" => rt, "bp" => bp, "state" => :Active, "brt" => brt} }
  end

  def handle_cast({:sendmsg, source, destination, no_hops}, state) do
    if(source == converttonode(destination)) do
      Tapestry.sendhop(no_hops)
    else
      pos = String.to_integer(String.at(destination, no_hops), 16)
      rt = state["rt"]
      new_source = rt[no_hops][pos]
      # new_source = converttonode(destination)
      if new_source == nil do
        Tapestry.sendhop(no_hops)
      else
        new_source = converttonode(new_source)
        GenServer.cast(new_source, {:sendmsg, new_source, destination, no_hops+1})
      end
    end
    {:noreply, state}
  end
  def handle_cast({:updatebackpointer, node, level}, state) do
    bp = state["bp"]
    new_bp = Map.put(bp, level, bp[level] ++ [node])
    {:noreply, Map.put(state, "bp", new_bp)}
  end
  def handle_cast({:removebp, level, node}, state) do
    bp = state["bp"]
    new_bp = Map.put(bp, level, bp[level] -- [node])
    {:noreply, Map.put(state, "bp", new_bp)}
  end

  def handle_cast({:setroutingtable, self, level, node}, state) do
    newstate = state
    rt = newstate["rt"]
    pos = String.to_integer(String.at(node, level), 16)
    cur_node = rt[level][pos]

    brt = newstate["brt"]
    blist = brt[level][pos]

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
      new_brt = (
        if(closer_node != cur_node) do
          blist = sortclosernodes(blist, self, cur_node)
          Map.put(brt, level, Map.put(brt[level], pos, Enum.uniq(blist)))
        else
          blist = sortclosernodes(blist, self, cur_node)
          Map.put(brt, level, Map.put(brt[level], pos, Enum.uniq(blist)))
        end
      )
      intstate = Map.put(newstate, "rt", new_rt)
      Map.put(intstate, "brt", new_brt)
    end)
    {:noreply, newstate}
  end

  def handle_cast({:reflectmessage, self, level, node}, state) do
    newstate = state
    rt = newstate["rt"]
    pos = String.to_integer(String.at(node, level), 16)
    cur_node = rt[level][pos]

    brt = newstate["brt"]
    blist = brt[level][pos]

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
      new_brt = (
        if(closer_node != cur_node) do
          # blist = blist ++ [cur_node]
          blist = sortclosernodes(blist, self, cur_node)
          # IO.inspect blist
          Map.put(brt, level, Map.put(brt[level], pos, Enum.uniq(blist)))
        else
          blist = sortclosernodes(blist, self, cur_node)
          Map.put(brt, level, Map.put(brt[level], pos, Enum.uniq(blist)))
        end
      )
      intstate = Map.put(newstate, "rt", new_rt)
      Map.put(intstate, "brt", new_brt)
    end)
    GenServer.cast(converttonode(node), {:setroutingtable, node, level, self})
    {:noreply, newstate}
  end

  def populateRT(node, list, n) do
    if(Map.has_key?(list, n) and Map.fetch!(list, n) != []) do
      findrootnodes(node, list[n])
    else
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

  def sortclosernodes(list,self,node) do
    if length(list) > 1 do
      index = (
        cond do
          finddis(node, self) < finddis(Enum.at(list, 0), self) -> 0
          finddis(node, self) < finddis(Enum.at(list, 1), self) -> 1
          finddis(node, self) < finddis(Enum.at(list, 2), self) -> 2
          true -> 3
        end
      )
      List.delete_at(List.insert_at(list, index, node), 3)
    else
      list ++ [node]
    end
  end

  def finddis(x, self) do
    dis_self = String.to_integer(self, 16)
    dis_x = String.to_integer(x, 16)
    abs(dis_self - dis_x)
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

  # To create RT and BP tables dynamically based on the no of identifier bits
  def createRT(noOfBits) do
    value = %{0 => nil,1 => nil,2 => nil,3 => nil,4 => nil,5 => nil,6 => nil,7 => nil,8 => nil,9 => nil,10 => nil,11 => nil,12 => nil,13 => nil,14 => nil,15 => nil}
    Enum.reduce(0..noOfBits-1, %{}, fn x,acc -> Map.put(acc, x , value) end)
  end

  def createBP(noOfBits) do
    Enum.reduce(0..noOfBits-1, %{}, fn x,acc -> Map.put(acc, x , []) end)
  end

  def createBRT(noOfBits) do
    value = %{0 => [],1 => [],2 => [],3 => [],4 => [],5 => [],6 => [],7 => [],8 => [],9 => [],10 => [],11 => [],12 => [],13 => [],14 => [],15 => []}
    Enum.reduce(0..noOfBits-1, %{}, fn x,acc -> Map.put(acc, x , value) end)
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
        [{_, failednode}] = :ets.lookup(:table,"failednodes")
        if(Map.fetch(failednode, new_source) == :error) do
          new_source = converttonode(new_source)
          Process.send_after(new_source, {:sendmsg, new_source, destination, no_hops+1}, 0)
        else
          backup = state["brt"]
          activebackup = (Enum.map(backup[no_hops][pos], fn n ->
            if(Map.fetch(failednode,n)==:error) do
              n
            end
          end) |> Enum.filter(& &1))
          if activebackup == [] do
            Tapestry.sendhop(no_hops)
          else
            new_source = converttonode(Enum.at(activebackup, 0))
            Process.send_after(new_source, {:sendmsg, new_source, destination, no_hops+1}, 0)
          end
        end
      end
    end
    {:noreply, state}
  end

  def failstatus node do
    [{_, failednode}] = :ets.lookup(:table,"failednodes")
    newfailednode = Map.put(failednode, node, node)
    :ets.insert(:table,{"failednodes", newfailednode})
    GenServer.cast(String.to_atom("N"<>node), {:failstatus})
  end

  def handle_cast({:failstatus}, state) do
    {:noreply, Map.put(state, "state", :failed)}
  end
end

