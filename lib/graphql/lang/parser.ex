defmodule GraphQL.Lang.Parser do

  def parse(tokens) do
    tokens |> document([])
  end

  defmacrop expect(expr) do
    quote location: :keep do
      case unquote(expr) do
        {:ok, item, rest} ->
          {rest, item}
        {:error, {ctx, message}} ->
          raise GraphQL.CompileError, line: ctx.line, col: ctx.col, description: message
      end
    end
  end

  defp collect_until(tokens, until, each, acc \\ []) do
    case until.(tokens) do
      {:ok, rest} -> {:ok, Enum.reverse(acc), rest}
      false ->
        {rest, item} = each.(tokens)
        collect_until(rest, until, each, [item|acc])
    end
  end

  defp one_of([], _) do
    {:error, :eof}
  end
  defp one_of([{_, ctx}|_], []) do
    {:error, {ctx, "Is not one of the expected kinds"}}
  end
  defp one_of(tokens, [fun|funs]) do
    case fun.(tokens) do
      {:ok, item, rest} -> {:ok, item, rest}
      {:error, _} -> one_of(tokens, funs)
    end
  end

  defp optional(tokens, fun, default \\ nil) do
    case fun.(tokens) do
      {:ok, item, rest} -> {rest, item}
      {:error, _} -> {tokens, default}
    end
  end

  defp document([], acc), do: {:document, Enum.reverse(acc)}
  defp document(tokens, acc) do
    {rest, item} = expect selection_set(tokens)
    document(rest, [item|acc])
  end

  defp selection_set([{:"{", ctx}|tokens]) do
    {rest, set} = expect collect_until(tokens,
        fn [{:"}", _}|tokens] -> {:ok, tokens}
           _ -> false
        end,
        &expect(field(&1))
      )
    {:ok, {:selection_set, ctx, set}, rest}
  end
  defp selection_set([{_, ctx}|_]) do
    {:error, {ctx, "Expected selection set"}}
  end

  defp variable([{:'$', ctx}, {{:identifier, name}, _}|tokens]) do
    {:ok, {:var, ctx, name}, tokens}
  end
  defp variable([{_,ctx}|_]) do
    {:error, {ctx, "Expected variable"}}
  end

  defp value([{_, ctx}|_]=tokens) do
    case one_of(tokens, [&variable/1]) do
      {:ok, value, tokens} -> {:ok, value, tokens}
      {:error, _} ->
        {:error, {ctx, "Expected value"}}
    end
  end

  defp argument([{{:identifier, name}, ctx}, {:':', _}|tokens]) do
    {tokens, value} = expect value(tokens)
    {:ok, {:argument, ctx, [name, value]}, tokens}
  end
  defp argument([{_,ctx}|_]=tokens) do
    IO.puts "tokens: #{inspect tokens}"
    {:error, {ctx, "Expected argument"}}
  end

  defp argument_list([{:"(", ctx}|tokens]) do
    {tokens, list} = expect collect_until(tokens,
        fn [{:")", _}|tokens] -> {:ok, tokens}
           _ -> false
        end,
        &expect(argument(&1))
      )
    {:ok, {:argument_list, ctx, list}, tokens}
  end
  defp argument_list([{_, ctx}|_]) do
    {:error, {ctx, "Expected argument list"}}
  end

  defp directive([{:@, ctx}, {{:identifier, name}, _}|tokens]) do
    {tokens, arguments} = optional tokens, &argument_list/1, []
    {:ok, {:directive, ctx, [name, arguments]}, tokens}
  end
  defp directive([{_, ctx}|_]) do
    {:error, {ctx, "Expected directive"}}
  end

  defp directives(tokens, acc \\ []) do
    case optional(tokens, &directive/1) do
      {^tokens, nil} -> {:ok, {:directives, %{}, Enum.reverse(acc)}, tokens}
      {tokens, directive} -> directives(tokens, [directive|acc])
    end
  end

  defp field([{{:identifier, field_alias}, ctx}, {:':', _}, {{:identifier, name}, _}|tokens]) do
    {tokens, args} = optional(tokens, &argument_list/1, [])
    {tokens, directives} = optional(tokens, &directives/1, [])
    {tokens, selection} = optional(tokens, &selection_set/1, [])
    {:ok, {:field, ctx, [field_alias, name, args, directives, selection]}, tokens}
  end
  defp field([{{:identifier, name}, ctx}|tokens]) do
    {tokens, args} = optional(tokens, &argument_list/1, [])
    {tokens, directives} = optional(tokens, &directives/1, [])
    {tokens, selection} = optional(tokens, &selection_set/1, [])
    {:ok, {:field, ctx, [nil, name, args, directives, selection]}, tokens}
  end
  defp field([{_,ctx}|_]=tokens) do
    IO.inspect tokens
    {:error, {ctx, "Expected field"}}
  end

end
