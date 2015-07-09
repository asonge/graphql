defmodule GraphqlLangParserTest do
  use ExUnit.Case

  alias GraphQL.Lang.Lexer
  alias GraphQL.Lang.Parser

  defp parse(str) do
    str |> Lexer.tokenize |> Parser.parse
  end

  test "basic query document" do
    assert {:document, [
      {:selection_set, _, [
        {:field, _, [nil, "foo", _, _, _]},
        {:field, _, [nil, "bar", _, _, _]}
      ]}
    ]} = parse("{ foo bar }")
  end

  test "nested selection set" do
    assert {:document, [
      {:selection_set, _, [
        {:field, _, [nil, "foo", _, _,
          {:selection_set, _, [
            {:field, _, [nil, "bar", _, _, _]}
          ]}
        ]}
      ]}
    ]} = parse("{ foo { bar }}")
  end

  test "alias and directives and arguments" do
    assert {:document, [
      {:selection_set, _, [
        {:field, _, [nil, "foo", _, {:directives, _, [
            {:directive, _, ["include",
              {:argument_list, _, [{:argument, _, ["if", {:var, _, "condition"}]}]}
            ]}
          ]}, {:selection_set, _, _}
        ]}
      ]}
    ]} = parse("{ foo @include(if: $condition){ bar }}")
  end

  test "normal arguments + alias" do
    assert {:document, [
      {:selection_set, _, [
        {:field, _, ["user_foo", "foo",
          {:argument_list, _, [{:argument, _, ["id", {:var, _, "id"}]}]}, _,
          {:selection_set, _, [
            {:field, _, [nil, "bar", _, _, _]}
          ]}
        ]}
      ]}
    ]} = parse("{ user_foo: foo(id: $id) { bar }}")
  end

end
