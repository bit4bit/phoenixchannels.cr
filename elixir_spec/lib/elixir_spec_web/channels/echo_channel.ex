defmodule ElixirSpecWeb.EchoChannel do
  @moduledoc """
  echo server para pruebas de integracion
  """
  use ElixirSpecWeb, :channel

  @impl true
  def join("echo:lobby", payload, socket) do
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end


  @impl true
  def handle_in("echo", payload, socket) do
    {:reply, payload, socket}
  end

  @impl true
  def handle_in("echo:broadcast", payload, socket) do
    broadcast(socket, "echo:broadcast", payload)
    {:noreply, socket}
  end

  defp authorized?(_payload) do
    true
  end
end
