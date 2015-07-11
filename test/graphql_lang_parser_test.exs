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
        {:field, _, ["foo", "foo", _, _, _]},
        {:field, _, ["bar", "bar", _, _, _]}
      ]}
    ]} = parse("{ foo bar }")
  end

  test "nested selection set" do
    assert {:document, [
      {:selection_set, _, [
        {:field, _, ["foo", "foo", _, _,
          {:selection_set, _, [
            {:field, _, ["bar", "bar", _, _, _]}
          ]}
        ]}
      ]}
    ]} = parse("{ foo { bar }}")
  end

  test "alias and directives and arguments" do
    assert {:document, [
      {:selection_set, _, [
        {:field, _, ["foo", "foo", _, {:directives, _, [
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
          {:argument_list, _, [
            {:argument, _, ["id", {:var, _, "id"}]},
            {:argument, _, ["a", 1]},
            {:argument, _, ["b", {:array, _, [1,2.0,3]}]},
            {:argument, _, ["c", {:object, _, %{"name" => "value"}}]}
          ]}, _,
          {:selection_set, _, [
            {:field, _, ["bar", "bar", _, _, _]}
          ]}
        ]}
      ]}
    ]} = parse(~S'{ user_foo: foo(id: $id, a: 1, b: [1,2.0,3], c: {name: "value"}) { bar }}')
  end

  test "basic query" do
    assert {:document, [
      {:query, _, [
        "getUser",
        {:variable_definitions, _, [
          {:argument_definition, _, ["id", {:type, _, "Integer"}, nil]}
        ]},
        _, # directives
        {:selection_set, _, [
          {:field, _, ["user", "user",
            {:argument_list, _, [
              {:argument, _, ["id", {:var, _, "id"}]}
            ]},
            _,
            {:selection_set, _, [
              {:field, _, ["id", "id", _, _, _]},
              {:field, _, ["name", "name", _, _, _]}
            ]}
          ]}
        ]}
      ]}
    ]} = parse("query getUser($id: Integer) { user(id: $id) { id, name } }")
  end

end
