defmodule Postgrestex do
  @moduledoc """
  Documentation for `Postgrestex`.
  """

  @spec init(map(), String.t()) :: map()
  def init(schema, path \\ "http://localhost:3000") do
    %{
      headers: %{
        Accept: "application/json",
        "Content-Type": "application/json",
        "Accept-Profile": schema,
        "Content-Profile": schema
      },
      path: path,
      schema: schema,
      method: "GET",
      negate_next: False,
      body: %{},
      params: %{}
    }
  end

  @spec auth(map(), String.t(), String.t(), String.t()) :: map()
  def auth(req, token, username \\ "", password \\ "") do
    # authenticate using the hackney client
    if username != "" do
      Map.merge(
        req,
        %{options: [hackney: [basic_auth: {username, password}]]}
      )
    else
      Map.put(
        req,
        :headers,
        Map.merge(req.headers, %{Authorization: "Bearer #{token}"})
      )
    end
  end

  @doc """
  Switch to another schema.

  ## Examples
  """
  @spec schema(map(), String.t()) :: map()
  def schema(req, schema) do
    Map.merge(req, %{schema: schema, method: "GET"})
  end

  @doc """
  Perform a table operation
  """
  @spec from(map(), String.t()) :: map()
  def from(req, table) do
    Map.merge(req, %{path: "#{req.path}/#{table}"})
  end

  @spec rpc(map(), String.t(), map()) :: map()
  def rpc(req, func, params) do
    # Append to path and set req type to post 
    Map.merge(req, %{path: "#{req.path}/#{func}", body: params, method: "POST"})
  end

  @spec call(map()) :: :ok | :error
  def call(req) do
    url = req.path
    headers = req.headers
    body = Poison.encode!(Map.get(req, :body, %{}))
    params = Map.get(req, :params, %{})
    options = Map.get(req, :options, [])

    case req.method do
      "POST" -> HTTPoison.post!(url, body, headers, params: params, options: options)
      "GET" -> HTTPoison.get!(url, headers, options: options)
      "PATCH" -> HTTPoison.patch!(url, %{}, headers, params: params, options: options)
      "DELETE" -> HTTPoison.delete!(url, params: params, options: options)
      _ -> IO.puts("Method not found!")
    end
  end

  @spec select(map(), list()) :: map()
  def select(req, columns) do
    Map.put(
      req,
      :headers,
      Map.merge(req.headers, %{select: Enum.join(columns, ","), method: "GET"})
    )
  end

  @spec insert(map(), list(), true | false) :: map()
  def insert(req, json, upsert \\ false) do
    prefer_option = if upsert, do: ",resolution=merge-duplicates", else: ""
    headers = Map.merge(req.headers, %{Prefer: prefer_option, method: "POST"})
    req |> Map.merge(headers) |> Map.merge(%{body: json})
  end

  @spec update(map(), map()) :: map()
  def update(req, json) do
    updated_headers = Map.merge(req.headers, %{Prefer: "return=representation"})

    updated_headers
    |> Map.merge(%{method: "PATCH", body: json})
    |> Map.merge(req)
  end

  @spec delete(map(), map()) :: map()
  def delete(req, json) do
    req |> Map.merge(%{method: "DELETE", body: json})
  end

  @spec order(map(), String.t(), true | false, true | false) :: map()
  def order(req, column, desc \\ false, nullsfirst \\ false) do
    desc = if desc, do: ".desc", else: ""
    nullsfirst = if nullsfirst, do: ".nullsfirst", else: ""
    headers = Map.merge(req.headers, %{order: "#{column} #{desc} #{nullsfirst}"})
    req |> Map.merge(headers)
  end

  @spec limit(map(), integer(), integer()) :: map()
  def limit(req, size, start) do
    Map.merge(req.headers, %{Range: "#{start}-#{start + size - 1}", "Range-Unit": "items"})
    |> Map.merge(req)
  end

  @spec range(map(), integer(), integer()) :: map()
  def range(req, start, end_) do
    updated_headers =
      Map.merge(req.headers, %{Range: "#{start}-#{end_ - 1}", "Range-Unit": "items"})

    updated_headers |> Map.merge(req)
  end

  @spec single(map()) :: map()
  def single(req) do
    # Modify this to use a session header
    Map.merge(req.headers, %{Accept: "application/vnd.pgrst.object+json"})
  end

  @spec sanitize_params(String.t()) :: String.t()
  def sanitize_params(str) do
    reserved_chars = String.graphemes(",.:()")
    if String.contains?(str, reserved_chars), do: str, else: "#{str}"
  end

  @spec sanitize_pattern_params(String.t()) :: String.t()
  def sanitize_pattern_params(str) do
    str |> String.replace("%", "*")
  end

  @spec filter(map(), String.t(), String.t(), String.t()) :: map()
  def filter(req, column, operator, criteria) do
    {req, operator} =
      if req.negate_next do
        {Map.update!(req, :negate_next, fn negate_next -> !negate_next end), "not.#{operator}"}
      end

    val = "#{operator}.#{criteria}"
    key = sanitize_params(column)

    req =
      if Map.has_key?(req.params, key),
        do: Map.update!(req.params, key, fn params -> params ++ [val] end),
        else: Kernel.put_in(req, [:params, key], val)

    Map.merge(req, %{method: "POST"})
  end

  @spec not map() :: map()
  def not req do
    Map.merge(req, %{negate_next: True})
  end

  @spec eq(map(), String.t(), String.t()) :: map()
  def eq(req, column, value) do
    filter(req, column, "eq", sanitize_params(value))
  end

  @spec neq(map(), String.t(), String.t()) :: map()
  def neq(req, column, value) do
    filter(req, column, "neq", sanitize_params(value))
  end

  @spec gt(map(), String.t(), String.t()) :: map()
  def gt(req, column, value) do
    filter(req, column, "gt", sanitize_params(value))
  end

  @spec lt(map(), String.t(), String.t()) :: map()
  def lt(req, column, value) do
    filter(req, column, "lt", sanitize_params(value))
  end

  @spec lte(map(), String.t(), String.t()) :: map()
  def lte(req, column, value) do
    filter(req, column, "lte", sanitize_params(value))
  end

  @spec is_(map(), String.t(), String.t()) :: map()
  def is_(req, column, value) do
    filter(req, column, "is", sanitize_params(value))
  end

  @spec like(map(), String.t(), String.t()) :: map()
  def like(req, column, pattern) do
    filter(req, column, "like", sanitize_pattern_params(pattern))
  end

  @spec ilike(map(), String.t(), String.t()) :: map()
  def ilike(req, column, pattern) do
    filter(req, column, "is", sanitize_params(pattern))
  end

  @spec fts(map(), String.t(), String.t()) :: map()
  def fts(req, column, query) do
    filter(req, column, "fts", sanitize_params(query))
  end

  @spec plfts(map(), String.t(), String.t()) :: map()
  def plfts(req, column, query) do
    filter(req, column, "plfts", sanitize_params(query))
  end

  @spec phfts(map(), String.t(), String.t()) :: map()
  def phfts(req, column, query) do
    filter(req, column, "phfts", sanitize_params(query))
  end

  @spec wfts(map(), String.t(), String.t()) :: map()
  def wfts(req, column, query) do
    filter(req, column, "wfts", sanitize_params(query))
  end

  def in_(req, column, values) do
    values = Enum.map(fn param -> sanitize_params(param) end, values) |> Enum.join(",")
    filter(req, column, "in", "(#{values})")
  end

  def cs(req, column, values) do
    values = Enum.map(fn param -> sanitize_params(param) end, values) |> Enum.join(",")
    filter(req, column, "cs", "{#{values}}")
  end

  def cd(req, column, values) do
    values = Enum.map(fn param -> sanitize_params(param) end, values) |> Enum.join(",")
    filter(req, column, "cd", "{#{values}}")
  end

  def ov(req, column, values) do
    values = Enum.map(fn param -> sanitize_params(param) end, values) |> Enum.join(",")
    filter(req, column, "ov", "{#{values}}")
  end

  @spec sl(map(), String.t(), integer()) :: map()
  def sl(req, column, range) do
    filter(req, column, "sl", "(#{Enum.at(range, 0)},#{Enum.at(range, 1)})")
  end

  @spec sr(map(), String.t(), integer()) :: map()
  def sr(req, column, range) do
    filter(req, column, "sr", "(#{Enum.at(range, 0)},#{Enum.at(range, 1)})")
  end

  @spec nxl(map(), String.t(), integer()) :: map()
  def nxl(req, column, range) do
    filter(req, column, "nxl", "(#{Enum.at(range, 0)},#{Enum.at(range, 1)})")
  end

  @spec nxr(map(), String.t(), integer()) :: map()
  def nxr(req, column, range) do
    filter(req, column, "nxr", "(#{Enum.at(range, 0)},#{Enum.at(range, 1)})")
  end

  @spec adj(map(), String.t(), integer()) :: map()
  def adj(req, column, range) do
    filter(req, column, "adj", "(#{Enum.at(range, 0)},#{Enum.at(range, 1)})")
  end
end
