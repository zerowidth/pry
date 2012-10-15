require 'pry/source_exporter'

class Pry
  Pry::Commands.create_command "save-source" do
    extend  Pry::Helpers::BaseHelpers

    group 'Introspection'
    description "Save the source for a method or class."

    banner <<-BANNER
      Usage: save-source [OPTIONS] [METH|CLASS]
      Aliases: $, show-method

      Show the source for a method or class. Tries instance methods first and then methods by default.

      e.g: `show-source Pry#rep`         # source for Pry#rep method
      e.g: `show-source Pry`             # source for Pry class

      https://github.com/pry/pry/wiki/Source-browsing#wiki-Show_method
    BANNER

    options :shellwords => false

    required_gems = ["diffy", "jist"]
    required_gems << "ruby18_source_location" if mri_18?
    options :requires_gem => required_gems

    def setup
      require 'ruby18_source_location' if mri_18?
      require 'diffy'
      require 'jist'
    end

    def process
      @code_object = retrieve_code_object_from_string(arg_string, target)
      case @code_object
      when Pry::Method
        save_method
      when Pry::WrappedModule
        save_module
      else
        raise Pry::CommandError, "#{arg_string} is not a valid method or class/module"
      end
    end

    def save_method
      exporter = SourceExporter.for(@code_object, 0)
      confirm_export(exporter)
    end

    def confirm_export(exporter, code=nil)
      show_diff(exporter, code)
      output.puts "If you are happy with the changes, press y<enter> to write the code to diskor E<edit> the code in an editor. Use ^D to cancel."
      answer = $stdin.gets.to_s.chomp
      if answer.upcase == "Y"
        exporter.export!(code)
        puts "Code exported and re-loaded!"
      elsif answer.upcase == "E"
        edit_file(exporter)
      else
        output.puts "Changes not saved."
      end
    end

    def edit_file(exporter)
      temp_file do |f|
        f.puts(exporter.target_file_content)
        f.flush
        f.close(false)
        Jist.copy(@code_object.source)
        invoke_editor(f.path, 1, false)
        confirm_export(exporter, File.read(f.path))
      end
    end

    def show_diff(exporter, code=nil)
      text_size = @code_object.source.lines.count

      # FIXME
      # this is a workaround for a fucking bug in Diffy
      # without this line it puts + before EVERY line in the diff 
      exporter.diff(code).to_s

      num_entries = code ? 1000 : text_size + 10
      
      out = %{
#{text.bold("Export diff for #{arg_string} method is: ")}
---

..clipped..
#{colorize_code exporter.diff(code).lines.to_a.last(num_entries).join}
}
      stagger_output out
    end
  end
end
