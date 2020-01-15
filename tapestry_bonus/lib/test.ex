defmodule Sample do
  def dif no do
    no
  end

  def calc do
    x = [1,3,4,5]
    result = (Enum.reduce(x, %{}, fn(x,acc) ->
      Map.put(acc, dif(x), x)
    end
    ))
    IO.inspect result
  end

  def test do
    res = (
      cond do
        5-2 == 2 -> "one"
        3-2 == 2 -> "two"
        true -> "thrid"
      end
    )

    IO.inspect res
  end
end
