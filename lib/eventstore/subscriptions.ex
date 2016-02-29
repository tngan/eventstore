defmodule EventStore.Subscriptions do
  use GenServer
  require Logger

  alias EventStore.Storage
  alias EventStore.Subscriptions
  alias EventStore.Subscriptions.Supervisor
  alias EventStore.Subscriptions.Subscription

  defstruct all_stream: [], single_stream: %{}, supervisor: nil

  @all_stream "$all"

  def start_link(supervisor) do
    GenServer.start_link(__MODULE__, %Subscriptions{
      all_stream: [],
      single_stream: %{},
      supervisor: supervisor
    })
  end

  def subscribe_to_stream(subscriptions, stream_uuid, subscription_name, subscriber) do
    GenServer.call(subscriptions, {:subscribe_to_stream, stream_uuid, subscription_name, subscriber})
  end
  
  def notify_events(subscriptions, stream_uuid, stream_version, events) do
    GenServer.cast(subscriptions, {:notify_events, stream_uuid, stream_version, events})
  end

  def init(%Subscriptions{} = subscriptions) do
    {:ok, subscriptions}
  end

  def handle_call({:subscribe_to_stream, stream_uuid, subscription_name, subscriber}, _from, %Subscriptions{supervisor: supervisor} = subscriptions) do
    {:ok, subscription} = Subscriptions.Supervisor.subscribe_to_stream(supervisor, stream_uuid, subscription_name, subscriber)

    subscriptions = case stream_uuid do
      @all_stream -> append_all_stream_subscription(subscriptions, subscription)
      stream_uuid -> append_single_stream_subscription(subscriptions, subscription, stream_uuid)
    end

    {:reply, {:ok, subscription}, subscriptions}
  end

  def handle_cast({:notify_events, stream_uuid, stream_version, events}, %Subscriptions{} = subscriptions) do
    interested_subscriptions = subscriptions.all_stream ++ Map.get(subscriptions.single_stream, stream_uuid, [])
    
    interested_subscriptions
    |> Enum.each(&Subscription.notify_events(&1, stream_uuid, stream_version, events))

    {:noreply, subscriptions}
  end

  defp append_all_stream_subscription(%Subscriptions{all_stream: all_stream} = subscriptions, subscription) do
    %Subscriptions{subscriptions | all_stream: [subscription | all_stream]}
  end

  defp append_single_stream_subscription(%Subscriptions{single_stream: single_stream} = subscriptions, subscription, stream_uuid) do
    {_, single_stream} = Map.get_and_update(single_stream, stream_uuid, fn current_value -> 
      new_value = case current_value do
        nil -> [subscription]
        current_value -> [subscription | current_value]
      end

      {current_value, new_value}
    end)

    %Subscriptions{subscriptions | single_stream: single_stream}
  end
end