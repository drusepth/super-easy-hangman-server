require 'socket' # TCPServer, TCPSocket

server = TCPServer.new('localhost', 9001)

def debug message, channel="debug"
  STDERR.puts "#{channel}: #{message}"
end

#todo allow more than 1 connection at a time
socket = server.accept
loop do
  input = socket.gets #blocking #todo allow for multi-line commands
  debug input

  socket.print input.upcase
end

socket.close
