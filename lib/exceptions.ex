defmodule GraphQL.CompileError do
  defexception file: nil, line: nil, col: nil, description: "Compile error"

  def message(exception) do
    "#{exception.description} on line #{exception.line} and column #{exception.col}"
  end

end
