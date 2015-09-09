require 'socket' # TCPServer, TCPSocket

server = TCPServer.new('localhost', 9001)

def debug message, channel=:debug
  STDERR.puts "#{channel}: #{message}"
end

def affirmative? input
  %w(y Y yes yep uh-huh).include? input
end

def negatory? input
  %w(n N no nope exit quit).include? input
end

class Game
  attr_accessor :socket, :state, :game

  STATES = %i(start_menu active_game game_over scoreboard about)

  class Hangman
    attr_accessor :current_word, :guessed_letters, :guesses_left, :notice

    def initialize
      self.current_word    = word_list.sample.chomp
      self.guessed_letters = []
      self.guesses_left    = 7
    end

    def word_list
      IO.readlines('wordlist.txt')
    rescue
      %w(bagels sandwich letters llama pancakes)
    end
    
    def valid_guess? input
      [
        !input.nil?,
        input.length == 1,
        !guessed_letters.include?(input)
      ].all?
    end
    
    def correct_guess? letter
      current_word.include?(letter)
    end
    
    def guess! letter
      return unless letter.chomp!.nil? && valid_guess?(letter)

      if correct_guess? letter
        self.notice = ["Good job!", "You got it!"].sample

      else
        guessed_incorrectly!
        self.notice = ["Nope!", "Not quite!"].sample
      end

      self.guessed_letters << letter
    end

    def guessed_correctly letter
    end

    def guessed_incorrectly!
      self.guesses_left -= 1
    end

    def game_over?
      won? || loss?
    end

    def won?
      self.guesses_left > 0 && !censored_word.include?('_') #todo actually check letters, not inverse
    end

    def loss?
      guesses_left < 1
    end    
    
    def censored_word
      current_word.chars.map do |c|
        guessed_letters.include?(c) ? c : '_'
      end.join ' '
    end

    def screen
      screen = [
        '  ___',
        ' |   `[0] ',
        ' |   [2][1][3]    [censored]',
        '"|    [1]       Guesses left: [guesses]',
        ' |   [5] [4]',
        ' |',
        ' ===================== Guessed: [guessed]',
        ' ##################### [notice]',
        '',
        ' Guess a letter to save the man: '
      ].map {|line| replace_body_parts line }
      .map {|line| tokenize line }

      screen.last.chomp!
      screen
    end


    def replace_body_parts line
      body_parts = { #todo config
        '0' => 'o',
        '1' => '|',
        '2' => '\\',
        '3' => '/',
        '4' => '\\',
        '5' => '/'
      }

      (0..5).each do |part_id| #todo this variable name is awful
        line.gsub! "[#{part_id}]", (guesses_left > part_id ? body_parts[part_id.to_s] : ' ')
      end

      line
    end

    def tokenize line
      line.gsub!('[censored]', censored_word) #todo dictionary these
      line.gsub!('[guessed]',  guessed_letters.sort.join(', '))
      line.gsub!('[guesses]',  guesses_left.to_s)
      line.gsub!('[notice]',   "~ #{self.notice}")
      line
    end
  end

  #todo allow writing to multiple sockets  
  def attach_socket output_socket
    @socket = output_socket
  end

  def transition_state new_state
    guard_method = "can_#{new_state}?"
    return if respond_to?(guard_method) && send(guard_method)
    return unless STATES.include? new_state
    
    debug "State: #{state} --> #{new_state}", :debug
    self.state = new_state

    initializer = "initialize_#{new_state}"
    send(initializer) if respond_to? initializer
  end
  
  def initialize_active_game
    debug 'Initializing a new Hangman game', :success
    self.game = Game::Hangman.new
  end

  def show_start_menu
    socket.puts [ #todo center text in bounding box
      'Welcome to the Super Easy Hangman Telnet Server (SETHS)',
      'Would you like to play a game? [y/n]'
    ].join "\r\n"
  end

  def show_game_over_screen
    screen = [
      "Game over!",
    ]
    screen << "Congratulations, you won!"            if game.won?
    screen << "Better luck next time!"               if game.loss?
    screen << "The word was '#{game.current_word}'." if game.loss?
    screen << "Want to give it another go? [y/n]"

    socket.puts screen.join "\r\n"
  end
  
  def play_game input
    game.guess! input.chomp
  end

  def draw_screen
    socket.puts game.screen.join("\r\n")
  end
  
end

#todo allow more than 1 connection at a time
debug "Server is now accepting connections.", :success
socket = server.accept

#todo should probably throw this loop in a thread
debug "A client has connected!", :success
game = Game.new
game.attach_socket socket

game.show_start_menu
game.transition_state :start_menu

input, skip_input = nil, nil #todo do you really have to init vars like this?

loop do
  # gets is blocking
  input = ""
  input = socket.gets unless skip_input
  skip_input = nil

  input.chomp!
  debug input, :input
  
  case game.state
  when :start_menu
    game.show_start_menu
    break                              if negatory? input
    game.transition_state :active_game if affirmative? input
    skip_input = true                  if affirmative? input

  when :active_game
    game.play_game input
    game.draw_screen

    if game.game.game_over? #dammit
      game.transition_state :game_over   
      skip_input = true
    end

  when :game_over
    game.show_game_over_screen
    break                              if negatory? input
    game.transition_state :active_game if affirmative? input
    skip_input = true                  if affirmative? input

  end
end

socket.close
