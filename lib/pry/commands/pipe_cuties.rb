Pry::Commands.block_command "grep", "grep stuff" do
  if in_pipe?
    obj = pipe.read

    if obj.respond_to?(:grep)
      grepped = obj.grep Regexp.new(arg_string)
    elsif obj.is_a?(String)
      grepped = obj.lines.to_a.grep Regexp.new(arg_string)
    else
      raise Pry::CommandError, "Can't grep passed object!"
    end

    if out_pipe?
      pipe.write grepped.join
    else
      output.puts grepped.join
    end

  else
    raise Pry::CommandError, "grep can only be used with piped input!"
  end
end

Pry::Commands.block_command "sort", "sort stuff" do
  if in_pipe?
    obj = pipe.read

    if obj.respond_to?(:sort_by)
      sorted = obj.sort_by { |v| text.strip_color(v.strip) }.join
    elsif obj.is_a?(String)
      sorted = obj.lines.to_a.sort_by { |v| text.strip_color(v.strip) }.join
    else
      raise Pry::CommandError, "Can't sort passed object!"
    end

    if out_pipe?
      pipe.write sorted
    else
      output.puts sorted
    end

  else
    raise Pry::CommandError, "sort can only be used with piped input!"
  end
end

Pry::Commands.block_command "less", "page stuff" do
  if in_pipe?
    obj = pipe.read

    if out_pipe?
      pipe.write obj
    else
      stagger_output obj.to_s
    end

  else
    raise Pry::CommandError, "can only be used with piped input!"
  end
end

Pry::Commands.block_command "wc", "page stuff" do
  if in_pipe?
    obj = pipe.read

    if obj.is_a?(String)
      count = obj.lines.count
    elsif obj.respond_to?(:count)
      count = obj.count
    else
      raise Pry::CommandError, "Can't count the object!"
    end

    if out_pipe?
      pipe.write count.to_s
    else
      output.puts "Number of lines: #{count.to_s}"
    end

  else
    raise Pry::CommandError, "can only be used with piped input!"
  end
end


Pry::Commands.block_command "less2", "page stuff" do
  if in_pipe?
    obj = pipe.read

    binding.pry

    if out_pipe?
      pipe.write obj
    else
      stagger_output obj.to_s
    end

  else
    raise Pry::CommandError, "sort can only be used with piped input!"
  end
end
