defmodule GraphqlLangLexerTest do
  use ExUnit.Case

  alias GraphQL.Lang.Lexer

  test "identifiers and position" do
    assert [{{:identifier, "omgwtf"}, %{line: 1, col: 1}}] = Lexer.tokenize("omgwtf")
    assert [{{:identifier, "omgwtf"}, %{line: 1, col: 1}},
            {{:identifier, "bbq"}, %{line: 1, col: 8}}] = Lexer.tokenize("omgwtf bbq")
  end

  test "line numbers reset column to 1" do
    assert [{{:identifier, "abc"}, %{line: 1, col: 1}},
            {{:identifier, "omgwtf"}, %{line: 2, col: 1}}] = Lexer.tokenize("abc\nomgwtf")
  end

  test "all line endings" do
    assert [{_, %{line: 1}},{_,%{line: 2}},{_,%{line: 3}},{_,%{line: 4}},{_,%{line: 5}},{_,%{line: 6}}] = Lexer.tokenize("1\r\n2\r3\n4\x{2028}5\x{2029}6")
  end

  test "all whitespace" do
    assert [_,_] = Lexer.tokenize("0\t\v\f, \xa01")
  end

  test "puncuators" do
    assert [{:!,_},{:..., _},{:|, %{col: 7}}] = Lexer.tokenize("! ... |")
  end

  test "ints" do
    assert [{23, _}, {-25, %{col: 4}}] = Lexer.tokenize("23,-25")
  end

  test "floats" do
    assert [{1.05e-123456789,_}] = Lexer.tokenize("1.05e-123456789")
    assert [{1.0,_}, {-3.5,_}, {0.0987654321,_}, {1.05e-3, %{col: 23}}] = Lexer.tokenize("1.0 -3.5 0.0987654321 1.05e-3")
  end

  test "strings" do
    assert [{{:str, "test"}, _}, {2,%{col: 8}}] = Lexer.tokenize(~S("test" 2))
    assert [{{:str, "\r"}, _}] = Lexer.tokenize(~S("\r"))
    assert [{{:str, "\x{2028}"}, _}, {_, %{col: 10}}] = Lexer.tokenize(~S("\u2028" abc))
    assert [{{:str, "\x{00CB}"}, _}, {_, %{col: 10}}] = Lexer.tokenize(~S("\u00Cb" abc))
    assert [{{:str, ""}, _}] = Lexer.tokenize(~S(""))
    assert [{{:str, " whitespace "}, _}] = Lexer.tokenize(~S(" whitespace "))
    assert [{{:str, "escaped \n\r\b\t\f"}, _}] = Lexer.tokenize(~S("escaped \n\r\b\t\f"))
    assert [{{:str, "quote \""}, _}] = Lexer.tokenize(~S("quote \""))
  end

  test "comments" do
    assert [] = Lexer.tokenize("#omg")
    assert [{{:identifier, "omg"}, _}] = Lexer.tokenize("omg#omg")
    assert [{{:identifier, "wtf"}, %{line: 2}}, {{:identifier, "bbq"}, %{line: 4}}] =
      Lexer.tokenize("""
        #omg
        wtf
        #bbbq
        bbq
      """)
  end

  # Is this valid lexing?
  test "00 weirdness" do
    assert [{0,_}, {0,_}] = Lexer.tokenize("00")
  end

  test "Bad numbers" do
    assert_raise GraphQL.CompileError, fn -> Lexer.tokenize("0.0.0") end
  end

  test "Bad strings" do
    assert_raise GraphQL.CompileError, fn -> Lexer.tokenize(~S(OMG \i)) end
    for line <- ["\r\n", "\r", "\n", "\x{2028}", "\x{2029}"] do
      assert_raise GraphQL.CompileError, fn -> Lexer.tokenize("\"omg#{line}wtf") end
    end
    assert_raise GraphQL.CompileError, fn -> Lexer.tokenize(~s("omg)) end
    assert_raise GraphQL.CompileError, fn -> Lexer.tokenize(~s("omg\\z")) end
  end

end
