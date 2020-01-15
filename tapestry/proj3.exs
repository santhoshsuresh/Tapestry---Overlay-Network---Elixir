defmodule Main do
  [numNodes,no_request] =Enum.map(System.argv, (fn x -> x end))
  numNodes = String.to_integer(numNodes)
  no_request = String.to_integer(no_request)

  NodeSupervisor.start_link(numNodes)
  starttime = System.os_time(:millisecond)

  Tapestry.start_link
  NodeSupervisor.sendmessage(no_request)

  NodeSupervisor.waitfunc(starttime, numNodes, no_request)

  [hop, _count] = Tapestry.gethop()
  IO.puts "Max hop value is #{hop}"

  Process.flag(:trap_exit, true)
end
