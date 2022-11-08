worker_processes 4

working_directory ENV['RAILS_ROOT']

listen "/app/unicorn.sock", :backlog => 1024, :tcp_nodelay => true, :tcp_nopush => false, :tries => 5, :delay => 0.5, :accept_filter => "httpready"

timeout 300

pid "/var/run/unicorn.pid"

stderr_path "/dev/stderr"
stdout_path "/dev/stdout"

preload_app true
GC.copy_on_write_friendly = true if GC.respond_to?(:copy_on_write_friendly=)

before_exec do |server|
  ENV['BUNDLE_GEMFILE'] = "/<%= ENV['RAILS_ROOT'] %>/Gemfile"
end

before_fork do |server, worker|
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.connection.disconnect!
  end

  old_pid = "/var/run/unicorn.pid.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end

after_fork do |server, worker|
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.establish_connection
  end
end