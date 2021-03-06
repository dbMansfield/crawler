require_relative 'commands'

class Mode
  @@max_history = 100
  attr_reader :regexp, :modifier_regexp, :commands, :history
  # modifiers should be a single regexp containing the modifiers
  # such as from or at
  def initialize(commands, modifiers = nil)
    @commands = commands
    # Shamelessly long one-liner
    @regexp = Regexp.new("(#{(0...@commands.length).each_with_object("") { |i, s| s << @commands[i][0].source << '|' }.chop})\\s+?(.*)")
    @modifier_regexp = (modifiers ? Regexp.new("(#{modifiers.source})\\s+(.*)") : nil)
    @history = []
  end

  def parse(player, input)
    # Check for history usage via ! syntax and replace input if needed
    # !n    nth command in history. First command is 1, not 0
    # !-n   nth command before this one in history
    # !!    shorthand for !-1
    /!(?:(-){0,1}(\d+))|(?:(!))/ =~ input
    if $1 || $3
      input = @history[-($2 || 1).to_i] # Need parens as nil.to_i == 0
    elsif $2
      input = @history[$2.to_i-1]
    end
    @history << input
    @history.shift if @history.length > @@max_history
    if /history/ =~ input
      @history.each_with_index { |x, i| puts "#{i+1}\t#{x}" }
      return :invalid # System commands shouldn't advance time either
    end

    input = input.downcase.split(@regexp).delete_if { |x| x.empty? }
    input[-1] = input[-1].split(@modifier_regexp).delete_if { |x| x.empty? } if @modifier_regexp
    input.flatten!
    # Reject definite article by removing substring of `the `
    input.map! { |x| x.strip.gsub(/the /, '') }

    if @commands.none? do |command|
        if command[0] =~ input[0]
          if !input[1] && command.length >= 4
            puts "#{input[0].capitalize} #{command.last || 'what'}?"
            return :invalid
          end
          outcome = self.method(command[1]).call(*[player, *eval(command[2] || '')]) 
          return (outcome == nil ? true : outcome)
        end
      end
      puts "Invalid command."
      return :invalid
    end
  end
end
# Each array entry is a new command, with a regexp to match
# the command against, a symbol for the function that the
# command should call, an optional string containing the
# arguments, and an optional string containing the interrogative
# of the error message if the arguments are not specified but
# should be. This string should be present if the arguments are
# compulsory, and should be absent otherwise. Would probably be
# easier with objects instead of arrays, but ah well. TODO?
$mode_explore = Mode.new([
  [/search/, :parse_search, 'input[1]'],
  [/take/, :parse_take, 'input[1..3]', 'what'],
  [/wield|equip|wear/, :parse_equip, 'input[1]', 'what'],
  [/examine|inspect/, :parse_examine, 'input[1]', 'what'],
  [/go/, :parse_go, 'input[1]', 'where'],
  [/look/, :parse_look, 'input[1..2]'],
  [/quit|exit/, :parse_exit],
  [/stats{0,1}|attributes{0,1}/, :parse_show_stat, ':all'],
  [/hp|health/, :parse_show_stat, ':hp'],
  [/str|strength/, :parse_show_stat, ':strength'],
  [/agl|agility/, :parse_show_stat, ':agility']],
  /from|at/
)

$mode_combat = Mode.new([
  [/attack|strike/, :parse_strike],
  [/wield|equip|wear/, :parse_equip, 'input[1]', 'what'],
  [/examine|inspect/, :parse_examine, 'input[1]', 'what'],
  [/flee/, :parse_flee],
  [/stats{0,1}|attributes{0,1}/, :parse_show_stat, ':all'],
  [/hp|health/, :parse_show_stat, ':hp'],
  [/str|strength/, :parse_show_stat, ':strength'],
  [/agl|agility/, :parse_show_stat, ':agility']]
)
