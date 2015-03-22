#!/usr/bin/ruby
require 'json'

require_relative 'modes'

class Item
  attr_reader :name, :description
  def initialize(name, description)
    @name = name
    @description = description
  end
end

class Weapon < Item
  attr_reader :damage
  def initialize(name, description, damage)
    super(name, description)
    @damage = damage
  end
end

class Armor < Item
  attr_reader :defense
  def initialize(name, description, defense)
    super(name, description)
    @defense = defense
  end
end

class Creature
  attr_reader :name, :description, :xp
  attr_accessor :hp, :strength, :agility, :evasion, :weapon, :armor, :items, :hostile
  def initialize(name, description, hp, strength, agility, evasion, xp, weapon = nil, armor = nil, hostile = false)
    @name, @description = name, description
    @hp, @strength, @agility, @evasion, @xp = hp, strength, agility, evasion, xp
    @weapon, @armor, @hostile = weapon, armor, hostile
    @items = []
  end

  # Attack the target creature. Returns the damage done, or nil for a miss
  def strike(target)
    return nil unless target.is_a? Creature
    if rand > target.evasion
      attack = @strength + (@weapon ? $items[@weapon].damage : 0)
      defense = target.agility + (target.armor ? $items[target.armor].defense : 0)
      if rand(32) != 0
        damage_base = (attack - defense / 2.0)
        damage = rand((damage_base / 4)..(damage_base / 2)).to_i
        damage = rand(2) if damage < 1
      else
        damage = rand((attack/2)..(attack))
      end
      target.hp -= damage
      damage
    else
      nil
    end
  end
end

class Player < Creature
  attr_accessor :area, :container, :enemy, :level
  def initialize(name, hp, strength, agility, evasion, area, container = 'here')
    super(name, "It's me", hp, strength, agility, evasion, 0)
    @area, @container, @enemy = area, container, nil
    @level = 1
  end

  def get_xp(xp)
    @xp += xp
    loop do
      break if @xp < 1.5*@level**3
      # Enough xp to level up
      @level += 1
      # This assignment is necessary as blocks/procs can't access their arguments
      # within themselves and we need to know the length of the longest
      # stat to tabulate correctly
      stats = [[:@strength, 6], [:@agility, 6], [:@hp, 6*1.3]]
      stats.each do |x|
        before = self.instance_variable_get(x[0])
        after = (before + 1 + x[1] * Math.tanh(@level / 30.0) * ((@level % 2) + 1)).to_i
        self.instance_variable_set(x[0], after)
        print x[0].to_s[1..-1].capitalize
        print ' '*(stats.max{|a,b|a[0].length<=>b[0].length}[0].length-x[0].length+1)
        puts "#{before}\t-> #{after}"
      end
    end
  end
end

# Description - String containing a description of the area
# without it's interactable contents
# Doors - Array containing all doors in the area which have
# the structure [description, location, target], where target is a
# string id for another area and location is a cardinal direction
# Items - Array of arrays of form [id, quantity]
# Creatures - Array of actual creatures in the area, NOT ids
class Area
  attr_reader :description, :doors, :items, :creatures
  def initialize(description, doors, items, creatures)
    @description, @doors, @items, @creatures = description, doors, items, creatures
  end
end

$items = File.open("items.json") { |f| JSON.load f }
$items.each do |k,v|
  type = k.split('_')[0].downcase
  if type == 'item'
    $items[k] = Item.new(v["name"], v["description"] || "")
  elsif type == 'weapon'
    $items[k] = Weapon.new(v["name"], v["description"] || "", v["damage"])
  elsif type == 'armor'
    $items[k] = Armor.new(v["name"], v["description"] || "", v["defense"])
  end
end

$creatures = File.open("creatures.json") { |f| JSON.load f }
$creatures.each do |k,v|
  $creatures[k] = Creature.new(
    v["name"] || "",
    v["description"] || "",
    v["hp"] || 1,
    v["strength"] || 1,
    v["agility"] || 1,
    v["evasion"] || 0,
    v["xp"] || 1,
    v["weapon"],
    v["armor"],
    v["hostile"] || false)
end

$areas = File.open("areas.json") { |f| JSON.load f }
$areas.each do |k,v|
  $areas[k] = Area.new(
    v["description"] || "",
    v["doors"] || [],
    v["items"] || [],
    v["creatures"] || [])
  # Can't use ids because creatures are different across areas, even if they
  # are the same type. Store a new instance of the actual creature instead
  if $areas[k].creatures
    $areas[k].creatures.map! { |x| [x, $creatures[x].dup] }
  end
end

# Prints the contents of the array using the format string fmt_str but adds
# natural english connectives. fmt_str must use self as the interpolation
# variable, and should be escaped accordingly
def format_list(array, fmt_str)
  str = ""
  array.each.with_index do |x, i|
    if array.length == 1
      x.instance_eval("str << \"#{fmt_str}\"")
    elsif i == array.length - 1
      x.instance_eval("str << \"and #{fmt_str}\"")
    else
      x.instance_eval("str << \"#{fmt_str}, \"")
    end
  end
  str
end

# Convert the command target into an actual object
def convert_command_target(player, target, containers_only = false)
  case target
  when 'here', 'the area', 'my surroundings'
    $areas[player.area]
  when 'me', 'myself', 'my bag'
    player
  else
    return $areas[player.area] if containers_only
    # Target type priority is
    # - Creature in the area
    # - Item in the player's surroundings
    # - Item in the player's current container
    # If still the target is not found, return nil
    if (creature = $areas[player.area].creatures.find { |x| x[1].name.downcase == target })
      creature[1]
    elsif (item = $areas[player.area].items.find { |x| $items[x[0]].name.downcase == target  })
      $items[item[0]]
    elsif (item = player.items.find { |x| $items[x[0]].name.downcase == target })
      $items[item[0]]
    else
      $areas[player.area]
    end
  end
end

puts "What's your name?"
$player = Player.new(gets.chomp, 15, 4, 4, 1.0/64, "area_01")

# explore - Movement and environment interaction
# combat - Fighting an enemy
$mode = :explore

$displayed_description = false
loop do
  case $mode
  when :explore
    unless $displayed_description
      puts '-'*40
      parse_look($player)
      $displayed_description = true
    end
    unless $areas[$player.area].creatures.empty?
      if (index = $areas[$player.area].creatures.index { |x| x[1].hostile })
        # Get the ID of enemy
        $player.enemy = $areas[$player.area].creatures[index][0]
        puts "The #{$creatures[$player.enemy].name} attacks!"
        $mode = :combat
        next
      end
    end
    print "> "
    $mode_explore.parse($player, gets.chomp!)
  when :combat
    print "~ "
    $mode_combat.parse($player, gets.chomp!) do
      enemy_index = $areas[$player.area].creatures.index { |x| x[0] == $player.enemy }
      enemy = $areas[$player.area].creatures[enemy_index][1]
      # Enemy dies
      if enemy.hp <= 0
        puts "The #{enemy.name} dies."
        # Grant experience
        puts "You gain #{enemy.xp} experience."
        $player.get_xp(enemy.xp)
        # Remove the dead enemy
        $areas[$player.area].creatures.delete_at(enemy_index)
        $mode = :explore
        next
      # Player dies
      elsif $player.hp <= 0
        puts "You die."
        exit
      # Combat still ongoing
      else
        # Enemy attacks the player so deal damage
        damage = enemy.strike($player)
        if damage
          puts "The #{enemy.name} strikes you for #{damage} damage."
        else
          puts "You evade the attack."
        end
        if $player.hp <= 0
          puts "You die."
          exit
        end
      end
    end
  end
end