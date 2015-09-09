require 'socket' # TCPServer, TCPSocket

server = TCPServer.new('localhost', 9001)

def debug message, channel=:debug
  STDERR.puts "#{channel}: #{message}"
end

class Game
  attr_accessor :socket, :state

  STATES = %i(start_menu active_game game_over)

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

  end

  def show_start_menu
    socket.puts [ #todo center text in bounding box
      'Welcome to the Super Easy Hangman Telnet Server (SETHS)',
      'Would you like to play a game?'
    ].join "\r\n"
  end
  
  def play_game command
    socket.puts [
      'You are currently playing.',
      "You typed #{command}"
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
game.state = :ready
input = nil

loop do
  socket.puts game.state
  
  case game.state
  when :ready
    game.show_start_menu
    game.transition_state :start_menu

  when :start_menu
    game.transition_state :active_game if input.chomp == 'y'

  when :active_game
    game.play_game input

  when :game_over
    game.transition_state :ready       if input.chomp == 'y'

  end
  
  input = socket.gets #blocking #todo allow for multi-line commands
  debug input
end

socket.close
