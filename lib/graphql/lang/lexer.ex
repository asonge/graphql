defmodule GraphQL.Lang.Lexer do
  @moduledoc """
  Turns a text GraphQL query into tokens.
  """

  @compile {:inline, bump: 1, bump: 2, hex: 1, hex: 4}

  def tokenize(source, opts \\ []) do
    filename = Keyword.get(opts, :filename, "-")
    tokens(source, %{line: 1, col: 1, filename: filename}, [])
  end

  @linebreaks ["\r\n", "\r", "\n", "\x{2028}", "\x{2029}"]
  @whitespace ' \t\v\f,'
  @identifier_start_chars [?A..?Z, ?a..?z] |> Enum.flat_map(&(&1))
  @identifier_chars [@identifier_start_chars, '_', ?0..?9] |> Enum.flat_map(&(&1))
  @punctuator_chars '!$():=@[]{|}'

  @sign ?-
  @zero ?0
  @nonzero_digit ?1..?9 |> Enum.to_list
  @digit [@zero|@nonzero_digit]
  @exponent ?e
  @string ?"
  @dot ?.

  @number_start [@sign|@digit]

  @hex_characters [?A..?F, ?a..?f, @digit] |> Enum.flat_map(&(&1))
  @escape_map %{?" => ?", ?\\ => ?\\, ?/ => ?/, ?b => ?\b, ?f => ?\f, ?n => ?\n, ?r => ?\r, ?t => ?\t}

  @comment ?#

  # eof
  defp tokens(<<>>, _, acc), do: Enum.reverse(acc)
  # whitespace/linebreaks
  for lb <- @linebreaks do
    defp tokens(<<unquote(lb)::binary, rest::binary>>, %{line: line}=ctx, acc) do
      tokens(rest, %{ctx|line: line+1, col: 1}, acc)
    end
  end
  defp tokens(<<"\xa0", rest::binary>>, ctx, acc) do
    tokens(rest, bump(ctx), acc)
  end
  for c <- @whitespace do
    defp tokens(<<unquote(c), rest::binary>>, ctx, acc) do
      tokens(rest, bump(ctx), acc)
    end
  end
  # Identifier detection
  for c <- @identifier_start_chars do
    defp tokens(<<unquote(c), _::binary>>=rest, ctx, acc) do
      {rest, ctx2, identifier} = id_tokens(rest, ctx, <<>>)
      tokens(rest, ctx2, [{{:identifier, identifier}, ctx}|acc])
    end
  end
  # Punctuation chars
  defp tokens(<<"...", rest::binary>>, ctx, acc) do
    tokens(rest, bump(ctx, 3), [{:'...', ctx}|acc])
  end
  for c <- @punctuator_chars do
    defp tokens(<<unquote(c), rest::binary>>, ctx, acc) do
      tokens(rest, bump(ctx), [{unquote(List.to_atom([c])), ctx}|acc])
    end
  end
  # Number stuff.
  for c <- @number_start do
    defp tokens(<<unquote(c), _::binary>>=rest, ctx, acc) do
      {rest, ctx2, number} = num_tokens(rest, ctx, [])
      tokens(rest, ctx2, [{number, ctx}|acc])
    end
  end
  defp tokens(<<@string, rest::binary>>, ctx, acc) do
    {rest, ctx2, str} = str_tokens(rest, bump(ctx), <<>>)
    tokens(rest, ctx2, [{{:str, str}, ctx}|acc])
  end
  defp tokens(<<@comment, rest::binary>>, ctx, acc) do
    {rest, ctx} = comment_tokens(rest, ctx)
    tokens(rest, ctx, acc)
  end
  defp tokens(rest, ctx, _) do
    raise GraphQL.CompileError, line: ctx.line, col: ctx.col, description: "Unexpected characters #{inspect rest}"
  end

  for c <- @identifier_chars do
    defp id_tokens(<<unquote(c), rest::binary>>, ctx, acc) do
      id_tokens(rest, bump(ctx), <<acc::binary, unquote(c)>>)
    end
  end
  defp id_tokens(rest, ctx, acc), do: {rest, ctx, acc}

  # Just short-circuit zero
  defp num_tokens(<<@zero, @dot, rest::binary>>, ctx, []), do: float_tokens(rest, bump(ctx, 2), '.0')
  defp num_tokens(<<@zero, rest::binary>>, ctx, []), do: {rest, bump(ctx), 0}
  defp num_tokens(<<@sign, rest::binary>>, ctx, []) do
    num_tokens(rest, bump(ctx), '-')
  end
  # Look for .
  for c <- @digit do
    defp num_tokens(<<@dot,unquote(c),rest::binary>>, ctx, acc) do
      float_tokens(rest, bump(ctx, 2), [unquote(c),@dot|acc])
    end
  end
  # Detect first digit, must be non-zero digit.
  for c <- @nonzero_digit do
    defp num_tokens(<<unquote(c), rest::binary>>, ctx, '-') do
      num_tokens(rest, bump(ctx), [unquote(c)|'-'])
    end
    defp num_tokens(<<unquote(c), rest::binary>>, ctx, []) do
      num_tokens(rest, bump(ctx), [unquote(c)])
    end
  end
  # Rest of the digits
  for c <- @digit do
    defp num_tokens(<<unquote(c), rest::binary>>, ctx, [s|_]=acc) when s !== @sign do
      num_tokens(rest, bump(ctx), [unquote(c)|acc])
    end
  end
  # Anything that finishes in num_tokens is actually an integer
  defp num_tokens(rest, ctx, acc) do
    {rest, ctx, acc |> Enum.reverse |> List.to_integer}
  end

  for c <- @digit do
    defp float_tokens(<<@exponent, @sign, unquote(c), rest::binary>>, ctx, acc) do
      float_tokens2(rest, bump(ctx, 3), [unquote(c), @sign, ?e|acc])
    end
    defp float_tokens(<<@exponent, unquote(c), rest::binary>>, ctx, acc) do
      float_tokens2(rest, bump(ctx, 2), [unquote(c), ?e|acc])
    end
  end
  for c <- @digit do
    defp float_tokens(<<unquote(c), rest::binary>>, ctx, acc) do
      float_tokens(rest, bump(ctx), [unquote(c)|acc])
    end
  end
  defp float_tokens(rest, ctx, acc) do
    {rest, ctx, acc |> Enum.reverse |> List.to_float}
  end

  # Only can be characters from here.
  for c <- @digit do
    defp float_tokens2(<<unquote(c), rest::binary>>, ctx, acc) do
      float_tokens2(rest, bump(ctx), [unquote(c)|acc])
    end
  end
  defp float_tokens2(rest, ctx, acc) do
    {rest, ctx, acc |> Enum.reverse |> List.to_float}
  end

  # End of string
  defp str_tokens(<<@string, rest::binary>>, ctx, acc) do
    {rest, bump(ctx), acc}
  end
  # No multiline strings
  for c <- @linebreaks do
    defp str_tokens(<<unquote(c), _::binary>>, ctx, _) do
      raise GraphQL.CompileError, line: ctx.line, col: ctx.col, description: "No multiline strings allowed."
    end
  end
  # Character by code
  defp str_tokens(<<?\\, ?u, a, b, c, d, rest::binary>>, ctx, acc) when
        a in @hex_characters and b in @hex_characters and
        c in @hex_characters and d in @hex_characters do
    char = :unicode.characters_to_binary([hex(a,b,c,d)])
    str_tokens(rest, bump(ctx, 6), <<acc::binary, char::binary>>)
  end
  # The normal escape sequences
  for {c,v} <- @escape_map do
    defp str_tokens(<<?\\, unquote(c), rest::binary>>, ctx, acc) do
      str_tokens(rest, bump(ctx, 2), <<acc::binary, unquote(v)>>)
    end
  end
  # Catch the unsupported escape sequence
  defp str_tokens(<<?\\, c, _::binary>>, ctx, _) do
    raise GraphQL.CompileError, line: ctx.line, col: ctx.col, description: "Illegal escape sequence #{[c]}"
  end
  defp str_tokens(<<c, rest::binary>>, ctx, acc) do
    str_tokens(rest, bump(ctx), <<acc::binary, c>>)
  end
  defp str_tokens(<<>>, ctx, _) do
    raise GraphQL.CompileError, line: ctx.line, col: ctx.col, description: "Unexpected end of file, expecting \""
  end

  for c <- @linebreaks do
    defp comment_tokens(<<unquote(c), rest::binary>>, %{line: line}=ctx) do
      {rest, %{ctx|line: line+1, col: 1}}
    end
  end
  defp comment_tokens(<<_, rest::binary>>, ctx), do: comment_tokens(rest, ctx)
  defp comment_tokens(<<>>, ctx), do: {<<>>, ctx}

  defp bump(%{col: col}=ctx, n \\ 1) do
    Map.put(ctx, :col, col+n)
  end

  defp hex(n) when n in ?a..?z, do: 10+n-?a
  defp hex(n) when n in ?A..?Z, do: 10+n-?A
  defp hex(n) when n in ?0..?9, do: n-?0
  defp hex(a,b,c,d) do
    hex(a)*16*16*16 + hex(b)*16*16 + hex(c)*16 + hex(d)
  end

end
