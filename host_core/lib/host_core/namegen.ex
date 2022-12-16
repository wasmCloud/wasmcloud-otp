defmodule HostCore.Namegen do
  @moduledoc """
  Generator for friendly names for hosts based on a random number. Names we pulled from a list of
  friendly or neutral adjectives and nouns suitable for use in public and on hosts/domain names
  """
  @adjectives ~w(
    autumn hidden bitter misty silent empty dry dark summer
    icy delicate quiet white cool spring winter patient
    twilight dawn crimson wispy weathered blue billowing
    broken cold damp falling frosty green long late lingering
    bold little morning muddy old red rough still small
    sparkling bouncing shy wandering withered wild black
    young holy solitary fragrant aged snowy proud floral
    restless divine polished ancient purple lively nameless
    gray orange mauve
  )

  @nouns ~w(
    waterfall river breeze moon rain wind sea morning
    snow lake sunset pine shadow leaf dawn glitter forest
    hill cloud meadow sun glade bird brook butterfly
    bush dew dust field fire flower firefly ladybug feather grass
    haze mountain night pond darkness snowflake silence
    sound sky shape stapler surf thunder violet water wildflower
    wave water resonance sun wood dream cherry tree fog autocorrect
    frost voice paper frog smoke star hamster ocean emoji robot
  )

  def generate(max_id \\ 9999) do
    adjective = Enum.random(@adjectives)
    noun = Enum.random(@nouns)
    id = :rand.uniform(max_id)

    Enum.join([adjective, noun, id], "-")
  end
end
