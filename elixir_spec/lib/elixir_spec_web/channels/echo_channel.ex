defmodule ElixirSpecWeb.EchoChannel do
  @moduledoc """
  echo server para pruebas de integracion
  """
  use ElixirSpecWeb, :channel
  require Logger

  @impl true
  def join("echo:lobby", payload, socket) do
    Logger.info("join to echo:lobby with payload: #{inspect(payload)}")
    schedule()
    
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end


  @impl true
  def handle_in("echo", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  @impl true
  def handle_in("echo:broadcast", payload, socket) do
    broadcast(socket, "echo:broadcast", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:heartbeat, socket) do
    schedule()

    push(socket, "heartbeat", %{"name" => "heartbeat"})
    {:noreply, socket}
  end

  defp authorized?(_payload) do
    true
  end

  defp schedule do
    Process.send_after(self(), :heartbeat, 100)
  end
end
