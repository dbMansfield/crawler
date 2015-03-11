require_relative 'commands'

# Each array entry is a new command, with a regexp to match
# the command against, a symbol for the function that the
# command should call, an optional string containing the
# arguments, and an optional string containing the interrogative
# of the error message if the arguments are not specified but
# should be. This string should be present if the arguments are
# compulsory, and should be absent otherwise. Would probably be
# easier with objects instead of arrays, but ah well. TODO?
EXPLORE_COMMANDS = [
  [/search/, :parse_search, 'input[1]'],
  [/take/, :parse_take, 'input[1..3]', 'what'],
  [/wield|equip|wear/, :parse_equip, 'input[1]', 'what'],
  [/examine|inspect/, :parse_examine, 'input[1]', 'what'],
  [/go/, :parse_go, 'input[1]', 'where'],
  [/look/, :parse_look],
  [/quit|exit/, :parse_exit]
]

def parse_explore(player, input)
  # Can't figure out the single regex with no internet so I'm cheating and
  # splitting it up. Besides, it works well enough
  input = input.downcase.split(/(search|take|quit|examine|inspect|equip|wield|wear|look|go|n)\s+?(.*)/).delete_if { |x| x.empty? }
  input[-1] = input[-1].split(/\s+(from)\s+(.*)/).delete_if { |x| x.empty? }
  input.flatten!
  area = $areas[player.area]

  if EXPLORE_COMMANDS.none? do |command|
      if command[0] =~ input[0]
        if !input[1] && command.length >= 4
          puts "#{input[0].capitalize} #{command.last || 'what'}?"
          break
        end
        self.method(command[1]).call(*[player, *eval(command[2] || '')])
        true # Hacky but whatever
      end
    end
    puts "Invalid command."
  end
end

def parse_combat(player, input)
  input = input.downcase.split(/(attack|strike|equip|wield|examine|wear)\s+?(.*)/).delete_if { |x| x.empty? }
  enemy = $areas[player.area].creatures.find { |x| x[0] == player.enemy }[1]

  outcome = nil

  if /attack|strike/ =~ input[0]
    if rand < 0.9
      damage = (player.weapon ? $items[player.weapon].damage : 1)
      enemy.hp -= damage
      puts "You strike the #{enemy.name} for #{damage} damage."
    else
      puts "The #{enemy.name} evades your attack."
    end
  elsif /equip|wield|wear/ =~ input[0]
    unless input[1]
      puts "#{input[0].capitalize} what?"
      return :invalid
    end
    outcome = parse_equip(player, input[1])
  elsif /examine|inspect/ =~ input[0]
    unless input[1]
      puts "#{input[0].capitalize} what?"
      return :invalid
    end
    outcome = parse_examine(player, input[1])
  else
    puts "Invalid command."
    outcome = :invalid
  end

  if enemy.hp <= 0
    outcome = :enemy_slain
  elsif player.hp <= 0
    outcome = :player_slain
  end

  return outcome
end