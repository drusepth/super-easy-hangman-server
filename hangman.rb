require 'socket' # TCPServer, TCPSocket

server = TCPServer.new('localhost', 9001)

def debug message, channel=:debug
  STDERR.puts "#{channel}: #{message}"
end

class Game
  attr_accessor :socket, :state, :game

  STATES = %i(start_menu active_game game_over scoreboard about)

  class Hangman
    attr_accessor :current_word, :guessed_letters, :guesses_left, :notice

    def initialize
      self.current_word    = word_list.sample
      self.guessed_letters = []
      self.guesses_left    = 7
    end

    def word_list
      %w(bagels sandwich letters)
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
      self.notice = "Passed"

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
        ' #####################',
        '',
        ' Guess a letter to save the man: '
      ].map {|line| replace_body_parts line }
      .map {|line| tokenize line }
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
        line.gsub! "[#{part_id}]", (guesses_left > part_id ? part_id.to_s : ' ')
      end

      line
    end

    def tokenize line
      line.gsub!('[censored]', censored_word) #todo dictionary these
      line.gsub!('[guessed]',  guessed_letters.join(', '))
      line.gsub!('[guesses]',  guesses_left.to_s)
      line
    end
  end

  #todo allow writing to multiple sockets  
  def attach_socket output_socket
    @socket = output_socket
  end

  def transition_state new_state
    puts "Transitioning #{state} --> #{new_state}"
    guard_method = "can_#{new_state}?"
    return if respond_to?(guard_method) && send(guard_method)
    puts "Guard clause passed"

    return unless STATES.include? new_state
    
    self.state = new_state
    puts "state is now #{state}"

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
      'Would you like to play a game?'
    ].join "\r\n"
  end
  
  def play_game input
    game.guess! input.chomp
  end

  def draw_screen
    screen = game.screen

    payload = screen + [
      'You are currently playing.',
      "You have #{game.guesses_left} guesses left",
      "The word is #{game.current_word}",
      "Censored is #{game.censored_word}",
    ]
    payload << "Notice #{game.notice}" if game.notice
    
    socket.puts payload.join("\r\n")
  end
  
  def game_over
    socket.puts [
      "Game over! Won? #{game.won?} / Lost? #{game.loss?}",
      'Play again?'
    ].join "\r\n"
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

input = nil

loop do
  socket.puts game.state

  input = socket.gets #blocking #todo allow for multi-line commands
  debug input, :input
  
  case game.state
  when :ready
    game.show_start_menu
    game.transition_state :start_menu

  when :start_menu
    game.transition_state :active_game if input.chomp == 'y'

  when :active_game
    game.play_game input
    game.draw_screen

    game.transition_state :game_over   if game.game.game_over? #dammit

  when :game_over
    game.transition_state :ready       if input.chomp == 'y'

  end
end

socket.close
