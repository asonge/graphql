defmodule GraphQL.CompileError do
  defexception file: nil, line: nil, column: nil, description: "Compile error"

  def message(exception) do
    "#{exception.description} on line #{exception.line} and column #{exception.column}"
  end

end
