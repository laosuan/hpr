require "./git/*"
require "terminal"

class Hpr::Git
  @@binary : String = `which git`.strip

  def self.ensure!
    raise NotFoundGitError.new("Not found git in PATH, Set it into PATH or install it.") if @@binary.empty?
  end

  def self.command(*args, path = ".", throw_error = false)
    ensure!

    Dir.cd(path) do
      cmd = args.to_a.compact.join(" ")
      Terminal.sh(binary, cmd, print_command: Hpr.verbose?, print_command_output: Hpr.verbose?, throw_error: throw_error).output
    end
  end

  def self.binary
    @@binary
  end

  getter path

  def initialize(@path : String)
  end

  def clone(url : String, name : String, mirror = false)
    output = exec("clone", mirror ? "--mirror" : "", url, name)
    @path = File.join(@path, name)
    output
  end

  def clone(url : String, mirror = false)
    name = File.basename(@path)
    @path = File.expand_path("../", @path)

    clone(url, name, mirror)
  end

  def remotes
    Hash(String, Remote).new.tap do |obj|
      exec("remote").split("\n").each do |name|
        pull_url = exec("remote get-url", name)
        push_url = exec("remote get-url --push", name)
        mirror = config("remote.#{name}.mirror", "false") == "true"
        obj[name] = Remote.new(self, name, pull_url, push_url, mirror)
      end
    end
  end

  def remote(name)
    remotes[name]
  end

  def add_remote(name, pull_url, push_url : String? = nil, mirror = false)
    exec("remote add", mirror ? "--mirror=push" : nil, name, pull_url)
    exec("remote set-url --push", name, push_url) if push_url

    push_url = pull_url unless push_url
    Remote.new(self, name, pull_url, push_url, mirror)
  end

  def update_remote(name, url, only_push = false)
    exec("remote set-url", only_push ? "--push" : nil, name, url)
  end

  def fetch_remote(name)
    exec("fetch", name)
  end

  def push_remote(name, mirror = false)
    exec("push", name, mirror ? "--mirror" : nil)
  end

  def delete_remote(name)
    exec("remote rm", name)
  end

  def tags
    exec("tag").split("\n")
  end

  def add_tag(name, message : String? = nil)
    exec("tag", message ? "-m #{message}" : nil, name)
  end

  def delete_tag(name)
    exec("tag -d", name)
  end

  def branches
    exec("branch | awk -F ' +' '! /\(no branch\)/ {print $2}'").split("\n")
  end

  def latest_hash
    exec("rev-parse HEAD")
  end

  def latest_tag
    exec("describe --tags --abbrev=0 2>/dev/null")
  end

  def config(key : String, default_value : (String | Int32 | Float64 | Bool)? = nil)
    if (value = exec("config --get", key)) && !value.empty?
      return value
    end

    default_value.to_s
  end

  def set_config(key : String, value)
    exec("config", key, quote_string(value))
  end

  def add_config(key : String, value)
    exec("config --add", key, quote_string(value))
  end

  def cloning?
    !repo?
  end

  def repo?
    Dir.cd(@path) do
      result = Terminal.test(Git.binary, "rev-parse --git-dir")
      return false if result && ![".", ".git"].includes?(exec("rev-parse --git-dir"))
      result
    end
  end

  def bare?
    exec("rev-parse --is-bare-repository") == "true"
  end

  def exists?
    Dir.exists?(@path)
  end

  def exec(*args, throw_error = false)
    Git.command(*args, path: @path, throw_error: throw_error)
  end

  private def has_refs?(path : String? = nil)
    path = path ? File.join(@path, path) : @path
    File.file?(File.join(path, "packed-refs"))
  end

  private def quote_string(text)
    text.is_a?(String) ? "'#{text}'" : text
  end

  record Remote, repo : Git, name : String, pull_url : String, push_url : String, mirror : Bool do
    def fetch
      repo.fetch_remote(name)
    end

    def push(mirror = false)
      repo.push_remote(name, mirror)
    end

    def set_url(url, only_push = false)
      repo.update_remote(name, url, only_push)
    end
  end
end
