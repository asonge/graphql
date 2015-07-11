defmodule GraphQL.Lang.Parser do

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

  def parse(tokens) do
    tokens |> document([])
  end

  defp document([], acc), do: {:document, Enum.reverse(acc)}
  defp document(tokens, acc) do
    {rest, item} = expect one_of(tokens, [&selection_set/1, &operation/1, &fragment_definition/1])
    document(rest, [item|acc])
  end

  defp name([{{:identifier, name},ctx}|tokens]), do: {:ok, {:name, ctx, name}, tokens}
  defp name(tokens), do: make_error(tokens, "name")

  defp operation([{{:identifier, operationType},ctx}|tokens]) when operationType in ["query","mutation"] do
    {tokens, {:name, _, name}} = expect name(tokens)
    {tokens, defs} = optional tokens, &variable_definitions/1
    {tokens, dirs} = optional tokens, &directives/1
    {tokens, selection} = expect selection_set(tokens)
    {:ok, {String.to_atom(operationType), ctx, [name, defs, dirs, selection]}, tokens}
  end
  defp operation(tokens), do: make_error(tokens, "operation")

  defp selection_set([{:"{", ctx}|tokens]) do
    {rest, set} = expect collect_until(tokens,
        fn [{:"}", _}|tokens] -> {:ok, tokens}
           _ -> false
        end,
        fn tokens1 -> expect(one_of tokens1, [&field/1, &fragment_spread/1, &inline_fragment/1]) end
      )
    {:ok, {:selection_set, ctx, set}, rest}
  end
  defp selection_set(tokens), do: make_error(tokens, "selection set")

  defp variable([{:'$', ctx}, {{:identifier, name}, _}|tokens]) do
    {:ok, {:var, ctx, name}, tokens}
  end
  defp variable(tokens), do: make_error(tokens, "variable")

  defp scalar_value([{value, _}|tokens]) when is_integer(value)
                                    or is_float(value)
                                    or value === true
                                    or value === false, do: {:ok, value, tokens}
  defp scalar_value(tokens), do: make_error(tokens, "scalar value")

  defp str_value([{{:str, value}, _}|tokens]), do: {:ok, value, tokens}
  defp str_value(tokens), do: make_error(tokens, "string value")

  defp array_value([{:"[", ctx}|tokens], const) do
    {tokens, items} = expect collect_until(tokens,
        fn [{:"]", _}|tokens] -> {:ok, tokens}
           _ -> false
        end,
        &expect(value(&1, const))
      )
    {:ok, {:array, ctx, items}, tokens}
  end
  defp array_value(tokens, _), do: make_error(tokens, "array")

  defp obj_field([{{:identifier, name}, _}, {:":",_}|tokens], const) do
    {tokens, value} = expect value(tokens, const)
    {:ok, {name, value}, tokens}
  end
  defp obj_field(tokens, _), do: make_error(tokens, "object field")

  defp obj_value([{:"{", ctx}|tokens], const) do
    {tokens, items} = expect collect_until(tokens,
        fn [{:"}", _}|tokens] -> {:ok, tokens}
           _ -> false
        end,
        &expect(obj_field(&1, const))
      )
    {:ok, {:object, ctx, items |> Enum.into(%{})}, tokens}
  end
  defp obj_value(tokens, _), do: make_error(tokens, "object")

  defp value([{_, ctx}|_]=tokens, const \\ false) do
    const_values = [&scalar_value/1, &str_value/1, &array_value(&1, const), &obj_value(&1, const)]
    values = if const do const_values else [(&variable/1)|const_values] end
    case one_of(tokens, values) do
      {:ok, value, tokens} -> {:ok, value, tokens}
      {:error, _} ->
        make_error(tokens, if const do "constant value" else "value" end)
    end
  end

  defp argument([{{:identifier, name}, ctx}, {:':', _}|tokens]) do
    {tokens, value} = expect value(tokens)
    {:ok, {:argument, ctx, [name, value]}, tokens}
  end
  defp argument(tokens), do: make_error(tokens, "argument")

  defp argument_list([{:"(", ctx}|tokens]) do
    {tokens, list} = expect collect_until(tokens,
        fn [{:")", _}|tokens] -> {:ok, tokens}
           _ -> false
        end,
        &expect(argument(&1))
      )
    {:ok, {:argument_list, ctx, list}, tokens}
  end
  defp argument_list(tokens), do: make_error(tokens, "argument list")

  defp argument_definition([{:"$",ctx}|tokens]) do
    {tokens, {:name, _, name}} = expect name(tokens)
    case tokens do
      [{:":",_}|tokens] ->
        {tokens, type} = expect type(tokens)
        {tokens, defaultValue} = optional tokens, &value(&1, true)
        {:ok, {:argument_definition, ctx, [name, type, defaultValue]}, tokens}
      tokens -> make_error(tokens, "argument separator ':'")
    end
  end
  defp argument_definition(tokens), do: make_error(tokens, "argument definition")

  defp type(tokens) do
    case tokens do
      [{:"[",ctx}|tokens] ->
        case expect(type(tokens)) do
          {[{:"]",_},{:"!",ctx2}|tokens], type} -> {:ok, {:list_type, ctx, {:not_null, ctx2, type}}, tokens}
          {[{:"]",_}|tokens], type} -> {:ok, {:list_type, ctx, type}, tokens}
          other -> other
        end
      [{{:identifier, name},ctx}, {:"!",ctx2}|tokens] -> {:ok, {:not_null, ctx2, {:type, ctx, name}}, tokens}
      [{{:identifier, name},ctx}|tokens] -> {:ok, {:type, ctx, name}, tokens}
      tokens -> make_error(tokens, "type")
    end
  end

  defp variable_definitions([{:"(", ctx}|tokens]) do
    {tokens, vars} = expect collect_until(tokens,
        fn [{:")", _}|tokens] -> {:ok, tokens}
           _ -> false
        end,
        &expect(argument_definition(&1))
      )
    {:ok, {:variable_definitions, ctx, vars}, tokens}
  end
  defp variable_definitions(tokens), do: make_error(tokens, "variable definitions")

  defp directive([{:@, ctx}, {{:identifier, name}, _}|tokens]) do
    {tokens, arguments} = optional tokens, &argument_list/1, []
    {:ok, {:directive, ctx, [name, arguments]}, tokens}
  end
  defp directive(tokens), do: make_error(tokens, "directive")

  defp directives(tokens, acc \\ []) do
    case optional(tokens, &directive/1) do
      {^tokens, nil} -> {:ok, {:directives, %{}, Enum.reverse(acc)}, tokens}
      {tokens, directive} -> directives(tokens, [directive|acc])
    end
  end

  defp inline_fragment([{:"...", ctx},{{:identifier, "on"}, _}|tokens]) do
    {tokens, type} = expect type(tokens)
    {tokens, dirs} = optional tokens, &directives/1, []
    {tokens, selection} = expect selection_set(tokens)
    {:ok, {:inline_fragment, ctx, [type, dirs, selection]}, tokens}
  end
  defp inline_fragment([{_,ctx}|tokens]), do: make_error(tokens, "inline fragment")

  defp fragment_spread([{:"...", ctx}|tokens]) do
    {tokens, {:name, _, name}} = expect(case name(tokens) do
      {:ok, {:name, ctx, "on"}, _} -> make_error(tokens, "not to get \"on\"")
      other -> other
    end)
    {tokens, dirs} = optional tokens, &directives/1, []
    {:ok, {:fragment_spread, ctx, [name, dirs]}, tokens}
  end
  defp fragment_spread([{_,ctx}|tokens]), do: make_error(tokens, "fragment spread")

  defp fragment_definition([{{:identifier, "fragment"}}|tokens]) do
    case tokens do
      [{{:identifier, name},_},{{:identifier, "on"},_}] when name !== "on" ->
        {tokens, type} = expect type(tokens)
        {tokens, dirs} = optional tokens, &directives/1, []
        {tokens, selection} = expect selection_set(tokens)
      tokens ->
        make_error(tokens)
    end
  end
  defp fragment_definition(tokens), do: make_error(tokens, "fragment definition")

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
    {:ok, {:field, ctx, [name, name, args, directives, selection]}, tokens}
  end
  defp field(tokens), do: make_error(tokens, "field")

  defp make_error([]), do: {:error, {%{}, "Unexpected end of file"}}
  defp make_error([{{:identifier, identifier},ctx}|_], token_name), do: {:error, {ctx, "Expected #{token_name}, got '#{identifier}'"}}
  defp make_error([{{:str, str},ctx}|_], token_name), do: {:error, {ctx, "Expected #{token_name}, got '#{inspect str}'"}}
  defp make_error([{token,ctx}|_], token_name), do: {:error, {ctx, "Expected #{token_name}, got '#{token}'"}}

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
  defp one_of([{_, ctx}|_], []), do: {:error, {ctx, "Is not one of the expected kinds"}}
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


end
