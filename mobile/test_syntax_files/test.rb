# Ruby sample file - Modern Ruby patterns
# frozen_string_literal: true

require 'json'
require 'time'
require 'set'
require 'securerandom'
require 'ostruct'
require 'digest'
require 'base64'
require 'uri'
require 'optparse'
require 'logger'
require 'forwardable'

# ===== Result Type =====

module Result
  class Success
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def success? = true
    def failure? = false

    def map
      Success.new(yield(value))
    end

    def flat_map
      yield(value)
    end

    def get_or_else(_default)
      value
    end

    def to_s
      "Success(#{value})"
    end
  end

  class Failure
    attr_reader :error

    def initialize(error)
      @error = error
    end

    def success? = false
    def failure? = true

    def map
      self
    end

    def flat_map
      self
    end

    def get_or_else(default)
      default
    end

    def to_s
      "Failure(#{error})"
    end
  end

  def self.ok(value) = Success.new(value)
  def self.err(error) = Failure.new(error)
end

# ===== Data Classes (Ruby 3.2+) =====

# Data.define creates immutable value objects
Point = Data.define(:x, :y) do
  def distance_from_origin = Math.sqrt(x**2 + y**2)
  def translate(dx, dy) = Point.new(x + dx, y + dy)
  def scale(factor) = Point.new(x * factor, y * factor)
  def to_a = [x, y]
end

Rectangle = Data.define(:top_left, :width, :height) do
  def area = width * height
  def perimeter = 2 * (width + height)
  def bottom_right = Point.new(top_left.x + width, top_left.y + height)
  def center = Point.new(top_left.x + width / 2.0, top_left.y + height / 2.0)
  def contains?(point) = point.x.between?(top_left.x, top_left.x + width) &&
                         point.y.between?(top_left.y, top_left.y + height)
end

Color = Data.define(:r, :g, :b, :a) do
  def self.rgb(r, g, b) = new(r, g, b, 255)
  def self.rgba(r, g, b, a) = new(r, g, b, a)
  def self.hex(hex_string)
    hex = hex_string.delete_prefix('#')
    r, g, b = hex.scan(/../).map { _1.to_i(16) }
    new(r, g, b, 255)
  end

  def to_hex = format('#%02X%02X%02X', r, g, b)
  def with_alpha(new_alpha) = Color.new(r, g, b, new_alpha)
  def blend(other, ratio = 0.5)
    Color.new(
      (r * (1 - ratio) + other.r * ratio).to_i,
      (g * (1 - ratio) + other.g * ratio).to_i,
      (b * (1 - ratio) + other.b * ratio).to_i,
      (a * (1 - ratio) + other.a * ratio).to_i
    )
  end
end

Credentials = Data.define(:username, :password_hash, :salt) do
  def self.create(username, password)
    salt = SecureRandom.hex(16)
    password_hash = Digest::SHA256.hexdigest(password + salt)
    new(username:, password_hash:, salt:)
  end

  def verify?(password)
    Digest::SHA256.hexdigest(password + salt) == password_hash
  end

  def to_safe_h = { username:, salt: }
end

# Immutable configuration
AppConfig = Data.define(:host, :port, :debug, :max_connections, :timeout) do
  def self.default
    new(host: 'localhost', port: 3000, debug: false, max_connections: 100, timeout: 30)
  end

  def self.from_env
    new(
      host: ENV.fetch('APP_HOST', 'localhost'),
      port: ENV.fetch('APP_PORT', '3000').to_i,
      debug: ENV.fetch('DEBUG', 'false') == 'true',
      max_connections: ENV.fetch('MAX_CONNECTIONS', '100').to_i,
      timeout: ENV.fetch('TIMEOUT', '30').to_i
    )
  end

  def with_debug(enabled) = AppConfig.new(host:, port:, debug: enabled, max_connections:, timeout:)
  def with_port(new_port) = AppConfig.new(host:, port: new_port, debug:, max_connections:, timeout:)
  def base_url = "http://#{host}:#{port}"
end

# ===== Pattern Matching =====

module PatternMatching
  # Pattern matching with case/in
  def self.describe_shape(shape)
    case shape
    in { type: :circle, radius: r }
      "Circle with radius #{r}, area: #{Math::PI * r**2}"
    in { type: :rectangle, width: w, height: h }
      "Rectangle #{w}x#{h}, area: #{w * h}"
    in { type: :triangle, base: b, height: h }
      "Triangle with base #{b}, height #{h}, area: #{0.5 * b * h}"
    in { type: :polygon, sides: sides } if sides.length >= 3
      "Polygon with #{sides.length} sides"
    else
      "Unknown shape"
    end
  end

  # Pattern matching with arrays
  def self.process_list(list)
    case list
    in []
      "Empty list"
    in [single]
      "Single element: #{single}"
    in [first, second]
      "Pair: #{first} and #{second}"
    in [first, *middle, last]
      "First: #{first}, Middle: #{middle.length} items, Last: #{last}"
    end
  end

  # Pattern matching with deconstruction
  def self.handle_response(response)
    case response
    in { status: 200..299, body: }
      Result.ok(body)
    in { status: 400..499, error: msg }
      Result.err("Client error: #{msg}")
    in { status: 500..599, error: msg }
      Result.err("Server error: #{msg}")
    in { status:, error: msg }
      Result.err("HTTP #{status}: #{msg}")
    else
      Result.err("Invalid response format")
    end
  end

  # Guard clauses in pattern matching
  def self.categorize_number(n)
    case n
    in Integer if n.negative?
      :negative
    in Integer if n.zero?
      :zero
    in Integer if n.positive? && n < 10
      :small_positive
    in Integer if n >= 10 && n < 100
      :medium_positive
    in Integer
      :large_positive
    in Float
      :floating_point
    else
      :not_a_number
    end
  end

  # Pattern matching with custom classes
  def self.process_event(event)
    case event
    in UserEvent(type: :created, payload: user)
      "User #{user.name} was created"
    in UserEvent(type: :updated, payload: user)
      "User #{user.name} was updated"
    in UserEvent(type: :deleted, payload: id)
      "User #{id} was deleted"
    else
      "Unknown event"
    end
  end

  # Rightward assignment with pattern matching
  def self.extract_coordinates(point)
    point => { x:, y: }
    [x, y]
  end

  # Find pattern (Ruby 3.0+)
  def self.find_admin(users)
    case users
    in [*, { role: :admin, name: } => admin, *]
      "Found admin: #{name}"
    else
      "No admin found"
    end
  end
end

# ===== Endless Methods =====

class MathUtils
  # Endless method definitions (Ruby 3.0+)
  def self.square(n) = n * n
  def self.cube(n) = n * n * n
  def self.double(n) = n * 2
  def self.half(n) = n / 2.0
  def self.abs(n) = n < 0 ? -n : n
  def self.clamp(n, min, max) = [[n, min].max, max].min
  def self.lerp(a, b, t) = a + (b - a) * t
  def self.factorial(n) = n <= 1 ? 1 : n * factorial(n - 1)
  def self.fibonacci(n) = n <= 1 ? n : fibonacci(n - 1) + fibonacci(n - 2)
  def self.gcd(a, b) = b.zero? ? a : gcd(b, a % b)
  def self.lcm(a, b) = (a * b).abs / gcd(a, b)
  def self.prime?(n) = n > 1 && (2..Math.sqrt(n)).none? { n % _1 == 0 }
  def self.degrees_to_radians(deg) = deg * Math::PI / 180
  def self.radians_to_degrees(rad) = rad * 180 / Math::PI
  def self.percentage(value, total) = (value.to_f / total * 100).round(2)
end

class StringUtils
  def self.blank?(s) = s.nil? || s.strip.empty?
  def self.present?(s) = !blank?(s)
  def self.truncate(s, length, suffix = '...') = s.length > length ? s[0...length] + suffix : s
  def self.camelize(s) = s.split('_').map(&:capitalize).join
  def self.underscore(s) = s.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
  def self.titleize(s) = s.split.map(&:capitalize).join(' ')
  def self.slugify(s) = s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
  def self.reverse_words(s) = s.split.reverse.join(' ')
  def self.palindrome?(s) = s.downcase.gsub(/[^a-z]/, '') == s.downcase.gsub(/[^a-z]/, '').reverse
  def self.word_count(s) = s.split.size
  def self.char_frequency(s) = s.chars.tally
end

# ===== Numbered Parameters =====

module NumberedParameterExamples
  # _1, _2, etc. are numbered block parameters (Ruby 2.7+)

  def self.double_all(numbers)
    numbers.map { _1 * 2 }
  end

  def self.filter_positive(numbers)
    numbers.select { _1.positive? }
  end

  def self.sum_pairs(pairs)
    pairs.map { _1 + _2 }
  end

  def self.format_entries(hash)
    hash.map { "#{_1}: #{_2}" }
  end

  def self.find_matching(items, pattern)
    items.find { _1.match?(pattern) }
  end

  def self.transform_nested(data)
    data.map { { key: _1[:name], value: _1[:count] * 2 } }
  end

  def self.zip_with_index(items)
    items.each_with_index.map { [_1, _2] }
  end

  def self.reduce_with_memo(items, initial = 0)
    items.reduce(initial) { _1 + _2 }
  end

  def self.partition_by_predicate(items)
    items.partition { _1 > 0 }
  end

  def self.group_by_first_char(words)
    words.group_by { _1[0] }
  end

  def self.sort_by_length(strings)
    strings.sort_by { _1.length }
  end

  def self.max_by_property(items, property)
    items.max_by { _1[property] }
  end
end

# ===== Hash Shorthand Syntax (Ruby 3.1+) =====

class Person
  attr_accessor :name, :age, :email, :city

  def initialize(name:, age:, email:, city:)
    @name = name
    @age = age
    @email = email
    @city = city
  end

  # Hash shorthand: { name: } instead of { name: name }
  def to_h
    { name:, age:, email:, city: }
  end

  def basic_info
    { name:, age: }
  end

  def contact_info
    { email:, city: }
  end

  def self.create(name, age, email, city)
    new(name:, age:, email:, city:)
  end
end

class OrderItem
  attr_reader :product_id, :quantity, :price, :discount

  def initialize(product_id:, quantity:, price:, discount: 0)
    @product_id = product_id
    @quantity = quantity
    @price = price
    @discount = discount
  end

  def total = quantity * price * (1 - discount)
  def to_h = { product_id:, quantity:, price:, discount:, total: }
end

# ===== Exception Handling =====

class NetworkError < StandardError; end
class TimeoutError < NetworkError; end
class ConnectionRefusedError < NetworkError; end
class AuthenticationError < StandardError; end
class ValidationError < StandardError
  attr_reader :errors
  def initialize(errors)
    @errors = errors
    super(errors.join(', '))
  end
end

module ExceptionHandling
  MAX_RETRIES = 3

  def self.fetch_with_retry(url)
    attempts = 0

    begin
      attempts += 1
      puts "Attempt #{attempts}: Fetching #{url}"

      # Simulate network request
      raise TimeoutError, "Request timed out" if rand < 0.3
      raise ConnectionRefusedError, "Connection refused" if rand < 0.2

      { status: 200, body: "Response from #{url}" }
    rescue TimeoutError => e
      puts "Timeout: #{e.message}"
      retry if attempts < MAX_RETRIES
      raise
    rescue ConnectionRefusedError => e
      puts "Connection refused: #{e.message}"
      sleep(0.5 * attempts) # Exponential backoff
      retry if attempts < MAX_RETRIES
      raise
    rescue StandardError => e
      puts "Unexpected error: #{e.class} - #{e.message}"
      raise
    ensure
      puts "Attempt #{attempts} completed"
    end
  end

  def self.safe_parse_json(json_string)
    JSON.parse(json_string, symbolize_names: true)
  rescue JSON::ParserError => e
    { error: "Invalid JSON: #{e.message}" }
  end

  def self.with_transaction
    puts "Starting transaction"
    result = yield
    puts "Committing transaction"
    result
  rescue StandardError => e
    puts "Rolling back transaction: #{e.message}"
    raise
  ensure
    puts "Cleaning up resources"
  end

  def self.validate_and_process(data)
    errors = []
    errors << "Name is required" if data[:name].nil? || data[:name].empty?
    errors << "Age must be positive" if data[:age].to_i <= 0
    errors << "Email is invalid" unless data[:email]&.include?('@')

    raise ValidationError.new(errors) unless errors.empty?

    { processed: true, data: }
  rescue ValidationError => e
    { processed: false, errors: e.errors }
  end

  # Rescue modifier
  def self.safe_divide(a, b)
    a / b rescue nil
  end

  # Multiple exception types
  def self.perform_operation(type)
    case type
    when :network then raise NetworkError, "Network failed"
    when :auth then raise AuthenticationError, "Auth failed"
    when :validation then raise ValidationError.new(["Invalid data"])
    else
      "Operation completed"
    end
  rescue NetworkError, AuthenticationError => e
    "Recoverable error: #{e.message}"
  rescue ValidationError => e
    "Validation failed: #{e.errors.join(', ')}"
  end
end

# ===== Blocks, Procs, and Lambdas =====

module BlocksProcsLambdas
  # Block with explicit block parameter
  def self.with_timing(&block)
    start_time = Time.now
    result = block.call
    elapsed = Time.now - start_time
    { result:, elapsed: }
  end

  # Block to Proc conversion
  def self.apply_to_all(items, &operation)
    items.map(&operation)
  end

  # Proc creation
  DOUBLE = proc { |n| n * 2 }
  SQUARE = proc { |n| n ** 2 }
  NEGATE = proc { |n| -n }

  # Lambda creation
  ADD = ->(a, b) { a + b }
  MULTIPLY = ->(a, b) { a * b }
  COMPOSE = ->(f, g) { ->(x) { g.call(f.call(x)) } }

  # Proc vs Lambda differences
  def self.demonstrate_proc_vs_lambda
    # Proc: relaxed argument checking
    relaxed_proc = proc { |a, b| [a, b] }
    puts "Proc with 1 arg: #{relaxed_proc.call(1)}"

    # Lambda: strict argument checking
    strict_lambda = ->(a, b) { [a, b] }
    begin
      strict_lambda.call(1)
    rescue ArgumentError => e
      puts "Lambda error: #{e.message}"
    end
  end

  # Currying
  def self.curried_operations
    add = ->(a, b, c) { a + b + c }
    curried_add = add.curry

    add_5 = curried_add.call(5)
    add_5_and_3 = add_5.call(3)
    result = add_5_and_3.call(2) # 10

    { curried_add:, add_5:, result: }
  end

  # Method to proc conversion
  def self.string_operations(strings)
    {
      upcased: strings.map(&:upcase),
      lengths: strings.map(&:length),
      reversed: strings.map(&:reverse),
      stripped: strings.map(&:strip)
    }
  end

  # Yielding to blocks
  def self.benchmark(label)
    start = Time.now
    result = yield
    elapsed = Time.now - start
    puts "#{label}: #{elapsed.round(4)}s"
    result
  end

  # Block with multiple yields
  def self.repeat(times)
    results = []
    times.times do |i|
      results << yield(i)
    end
    results
  end

  # Storing blocks for later execution
  class DeferredExecutor
    def initialize
      @tasks = []
    end

    def defer(&block)
      @tasks << block
    end

    def execute_all
      @tasks.map(&:call)
    end

    def execute_with_args(*args)
      @tasks.map { |task| task.call(*args) }
    end
  end
end

# ===== Method Visibility =====

class Account
  attr_reader :owner, :balance

  def initialize(owner, initial_balance = 0)
    @owner = owner
    @balance = initial_balance
    @transaction_log = []
  end

  # Public methods (default)
  def deposit(amount)
    validate_amount!(amount)
    process_deposit(amount)
    log_transaction(:deposit, amount)
    balance
  end

  def withdraw(amount)
    validate_amount!(amount)
    validate_sufficient_funds!(amount)
    process_withdrawal(amount)
    log_transaction(:withdrawal, amount)
    balance
  end

  def transfer_to(other_account, amount)
    validate_amount!(amount)
    validate_sufficient_funds!(amount)
    validate_transfer_allowed!(other_account)

    perform_transfer(other_account, amount)
  end

  def statement
    generate_statement
  end

  protected

  # Protected: accessible by same class or subclasses
  def receive_transfer(amount, from_account)
    @balance += amount
    log_transaction(:transfer_in, amount, from: from_account.owner)
  end

  def perform_transfer(other_account, amount)
    process_withdrawal(amount)
    other_account.receive_transfer(amount, self)
    log_transaction(:transfer_out, amount, to: other_account.owner)
  end

  def can_receive_transfers? = true

  private

  # Private: only accessible within the class
  def validate_amount!(amount)
    raise ArgumentError, "Amount must be positive" unless amount.positive?
  end

  def validate_sufficient_funds!(amount)
    raise ArgumentError, "Insufficient funds" if amount > @balance
  end

  def validate_transfer_allowed!(other_account)
    raise ArgumentError, "Cannot transfer to self" if other_account == self
    raise ArgumentError, "Account cannot receive transfers" unless other_account.can_receive_transfers?
  end

  def process_deposit(amount)
    @balance += amount
  end

  def process_withdrawal(amount)
    @balance -= amount
  end

  def log_transaction(type, amount, metadata = {})
    @transaction_log << {
      type:,
      amount:,
      balance: @balance,
      timestamp: Time.now,
      **metadata
    }
  end

  def generate_statement
    @transaction_log.map do |txn|
      "#{txn[:timestamp].strftime('%Y-%m-%d %H:%M')} | #{txn[:type]} | $#{txn[:amount]} | Balance: $#{txn[:balance]}"
    end.join("\n")
  end
end

class SavingsAccount < Account
  INTEREST_RATE = 0.05

  def apply_interest
    interest = calculate_interest
    process_deposit(interest)
    log_transaction(:interest, interest)
    interest
  end

  private

  def calculate_interest
    (@balance * INTEREST_RATE).round(2)
  end
end

# ===== Module Mixins =====

module Loggable
  def log(message, level: :info)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    puts "[#{timestamp}] [#{level.upcase}] [#{self.class}] #{message}"
  end

  def log_info(message) = log(message, level: :info)
  def log_warn(message) = log(message, level: :warn)
  def log_error(message) = log(message, level: :error)
  def log_debug(message) = log(message, level: :debug)
end

module Serializable
  def to_json(*args)
    serializable_attributes.to_json(*args)
  end

  def to_yaml
    require 'yaml'
    serializable_attributes.to_yaml
  end

  def serializable_attributes
    instance_variables.each_with_object({}) do |var, hash|
      key = var.to_s.delete_prefix('@').to_sym
      hash[key] = instance_variable_get(var)
    end
  end
end

module Comparable
  def <=>(other)
    return nil unless other.is_a?(self.class)
    comparison_value <=> other.comparison_value
  end

  def <(other) = (self <=> other) == -1
  def >(other) = (self <=> other) == 1
  def <=(other) = (self <=> other) <= 0
  def >=(other) = (self <=> other) >= 0
  def ==(other) = (self <=> other) == 0

  def between?(min, max)
    self >= min && self <= max
  end
end

module Cacheable
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def cache
      @cache ||= {}
    end

    def cached(key, &block)
      return cache[key] if cache.key?(key)
      cache[key] = block.call
    end

    def clear_cache
      @cache = {}
    end

    def cache_method(method_name)
      original_method = instance_method(method_name)

      define_method(method_name) do |*args|
        cache_key = [method_name, args]
        self.class.cached(cache_key) { original_method.bind(self).call(*args) }
      end
    end
  end
end

# Prepend example
module Timestamped
  def save
    @updated_at = Time.now
    @created_at ||= Time.now
    super
  end

  attr_reader :created_at, :updated_at
end

# Include vs Extend vs Prepend demonstration
class Document
  include Loggable      # Instance methods
  include Serializable  # Instance methods
  prepend Timestamped   # Overrides save with super chain

  attr_accessor :title, :content, :author

  def initialize(title:, content:, author:)
    @title = title
    @content = content
    @author = author
  end

  def save
    log_info("Saving document: #{title}")
    # Actual save logic
    true
  end

  def word_count = content.split.size
  def char_count = content.length
end

# ===== Refinements =====

module StringRefinements
  refine String do
    def to_slug
      downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
    end

    def truncate_words(count, suffix = '...')
      words = split
      return self if words.length <= count
      words.first(count).join(' ') + suffix
    end

    def titlecase
      split.map(&:capitalize).join(' ')
    end

    def remove_accents
      tr('àáâãäåèéêëìíîïòóôõöùúûü', 'aaaaaaeeeeiiiioooooouuuu')
    end

    def to_boolean
      %w[true yes 1 on].include?(downcase.strip)
    end
  end
end

module ArrayRefinements
  refine Array do
    def second = self[1]
    def third = self[2]
    def fourth = self[3]
    def fifth = self[4]

    def average
      return nil if empty?
      sum.to_f / size
    end

    def median
      return nil if empty?
      sorted = sort
      mid = size / 2
      size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    def mode
      return nil if empty?
      tally.max_by { _2 }&.first
    end

    def pluck(*keys)
      map { |item| keys.map { |k| item[k] } }
    end

    def without(*values)
      self - values
    end
  end
end

module HashRefinements
  refine Hash do
    def deep_merge(other)
      merge(other) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          old_val.deep_merge(new_val)
        else
          new_val
        end
      end
    end

    def deep_symbolize_keys
      transform_keys(&:to_sym).transform_values do |v|
        v.is_a?(Hash) ? v.deep_symbolize_keys : v
      end
    end

    def slice(*keys)
      select { |k, _| keys.include?(k) }
    end

    def except(*keys)
      reject { |k, _| keys.include?(k) }
    end

    def compact_blank
      reject { |_, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
    end
  end
end

# Using refinements
class ContentProcessor
  using StringRefinements
  using ArrayRefinements

  def process_titles(titles)
    titles.map(&:titlecase)
  end

  def create_slugs(titles)
    titles.map(&:to_slug)
  end

  def analyze_lengths(texts)
    lengths = texts.map(&:length)
    { average: lengths.average, median: lengths.median, mode: lengths.mode }
  end
end

# ===== Struct =====

# Classic Struct
Person2 = Struct.new(:name, :age, :email, keyword_init: true) do
  def adult? = age >= 18
  def greeting = "Hello, I'm #{name}"
  def to_s = "#{name} (#{age})"
end

# Struct with validation
Address = Struct.new(:street, :city, :state, :zip, keyword_init: true) do
  def valid?
    [street, city, state, zip].all? { _1 && !_1.empty? }
  end

  def full_address
    "#{street}, #{city}, #{state} #{zip}"
  end

  def state_abbr = state.upcase[0, 2]
end

# Struct for configuration
DatabaseConfig = Struct.new(:host, :port, :database, :username, :password, keyword_init: true) do
  def connection_string
    "postgresql://#{username}:#{password}@#{host}:#{port}/#{database}"
  end

  def to_h_safe
    to_h.except(:password).merge(password: '***')
  end
end

# ===== OpenStruct =====

class DynamicConfig
  def initialize(defaults = {})
    @config = OpenStruct.new(defaults)
  end

  def method_missing(method, *args, &block)
    if method.to_s.end_with?('=')
      @config.send(method, *args)
    else
      @config.send(method)
    end
  end

  def respond_to_missing?(method, include_private = false)
    true
  end

  def to_h
    @config.to_h
  end

  def freeze
    @config.freeze
    super
  end
end

# OpenStruct for flexible responses
class ApiResponse
  def initialize(data)
    @data = OpenStruct.new(data)
  end

  def success? = @data.status == 'success'
  def error? = @data.status == 'error'
  def message = @data.message
  def payload = @data.payload

  def [](key)
    @data[key]
  end
end

# ===== Method Chaining =====

class QueryBuilder
  def initialize(table)
    @table = table
    @selects = []
    @conditions = []
    @order = nil
    @limit_value = nil
    @offset_value = nil
    @joins = []
    @group_by = nil
  end

  def select(*columns)
    @selects.concat(columns)
    self
  end

  def where(condition)
    @conditions << condition
    self
  end

  def and_where(condition)
    where(condition)
  end

  def or_where(condition)
    @conditions << "OR #{condition}"
    self
  end

  def order(column, direction = :asc)
    @order = "#{column} #{direction.upcase}"
    self
  end

  def limit(n)
    @limit_value = n
    self
  end

  def offset(n)
    @offset_value = n
    self
  end

  def join(table, on:, type: :inner)
    @joins << "#{type.upcase} JOIN #{table} ON #{on}"
    self
  end

  def group(*columns)
    @group_by = columns.join(', ')
    self
  end

  def to_sql
    sql = []
    sql << "SELECT #{@selects.empty? ? '*' : @selects.join(', ')}"
    sql << "FROM #{@table}"
    sql.concat(@joins)
    sql << "WHERE #{@conditions.join(' AND ')}" unless @conditions.empty?
    sql << "GROUP BY #{@group_by}" if @group_by
    sql << "ORDER BY #{@order}" if @order
    sql << "LIMIT #{@limit_value}" if @limit_value
    sql << "OFFSET #{@offset_value}" if @offset_value
    sql.join("\n")
  end

  alias build to_sql
end

# Fluent interface for string building
class HtmlBuilder
  def initialize
    @content = []
    @indent_level = 0
  end

  def tag(name, attributes = {}, &block)
    attrs = attributes.map { |k, v| "#{k}=\"#{v}\"" }.join(' ')
    opening = attrs.empty? ? "<#{name}>" : "<#{name} #{attrs}>"

    @content << "#{'  ' * @indent_level}#{opening}"

    if block_given?
      @indent_level += 1
      instance_eval(&block)
      @indent_level -= 1
      @content << "#{'  ' * @indent_level}</#{name}>"
    else
      @content[-1] = @content[-1].sub(">", "/>")
    end

    self
  end

  def text(content)
    @content << "#{'  ' * @indent_level}#{content}"
    self
  end

  def div(attributes = {}, &block) = tag(:div, attributes, &block)
  def span(attributes = {}, &block) = tag(:span, attributes, &block)
  def p(attributes = {}, &block) = tag(:p, attributes, &block)
  def h1(attributes = {}, &block) = tag(:h1, attributes, &block)
  def h2(attributes = {}, &block) = tag(:h2, attributes, &block)
  def a(href:, &block) = tag(:a, { href: }, &block)
  def img(src:, alt:) = tag(:img, { src:, alt: })

  def build = @content.join("\n")
  alias to_s build
end

# ===== DSL Patterns =====

class TaskDSL
  def initialize
    @tasks = []
  end

  def task(name, &block)
    task_def = TaskDefinition.new(name)
    task_def.instance_eval(&block) if block_given?
    @tasks << task_def
  end

  def tasks = @tasks

  class TaskDefinition
    attr_reader :name, :dependencies, :action

    def initialize(name)
      @name = name
      @dependencies = []
      @action = nil
      @description = nil
    end

    def depends_on(*task_names)
      @dependencies.concat(task_names)
    end

    def desc(description)
      @description = description
    end

    def run(&block)
      @action = block
    end

    def execute
      @action&.call
    end
  end

  def self.define(&block)
    dsl = new
    dsl.instance_eval(&block)
    dsl
  end
end

# Route DSL
class Router
  def initialize
    @routes = []
  end

  def get(path, to:, as: nil)
    @routes << { method: :get, path:, handler: to, name: as }
    self
  end

  def post(path, to:, as: nil)
    @routes << { method: :post, path:, handler: to, name: as }
    self
  end

  def put(path, to:, as: nil)
    @routes << { method: :put, path:, handler: to, name: as }
    self
  end

  def delete(path, to:, as: nil)
    @routes << { method: :delete, path:, handler: to, name: as }
    self
  end

  def patch(path, to:, as: nil)
    @routes << { method: :patch, path:, handler: to, name: as }
    self
  end

  def resources(name, only: nil, except: nil)
    actions = %i[index show create update destroy]
    actions = actions & only if only
    actions = actions - except if except

    actions.each do |action|
      case action
      when :index then get("/#{name}", to: "#{name}#index", as: name)
      when :show then get("/#{name}/:id", to: "#{name}#show", as: :"#{name}_show")
      when :create then post("/#{name}", to: "#{name}#create", as: :"#{name}_create")
      when :update then put("/#{name}/:id", to: "#{name}#update", as: :"#{name}_update")
      when :destroy then delete("/#{name}/:id", to: "#{name}#destroy", as: :"#{name}_destroy")
      end
    end
    self
  end

  def namespace(prefix, &block)
    nested_router = Router.new
    nested_router.instance_eval(&block)
    nested_router.routes.each do |route|
      @routes << route.merge(path: "/#{prefix}#{route[:path]}")
    end
    self
  end

  def routes = @routes

  def self.draw(&block)
    router = new
    router.instance_eval(&block)
    router
  end
end

# Configuration DSL
class AppConfigurator
  attr_reader :settings

  def initialize
    @settings = {}
  end

  def database(&block)
    @settings[:database] = DatabaseSettings.new
    @settings[:database].instance_eval(&block)
  end

  def cache(&block)
    @settings[:cache] = CacheSettings.new
    @settings[:cache].instance_eval(&block)
  end

  def logging(&block)
    @settings[:logging] = LoggingSettings.new
    @settings[:logging].instance_eval(&block)
  end

  def self.configure(&block)
    config = new
    config.instance_eval(&block)
    config
  end

  class DatabaseSettings
    attr_accessor :adapter, :host, :port, :database, :pool_size

    def connection_string
      "#{adapter}://#{host}:#{port}/#{database}"
    end
  end

  class CacheSettings
    attr_accessor :store, :ttl, :namespace
  end

  class LoggingSettings
    attr_accessor :level, :output, :format
  end
end

# ===== Metaprogramming =====

module Metaprogramming
  # define_method
  class AttributeAccessor
    def self.attr_with_default(name, default)
      define_method(name) do
        instance_variable_get("@#{name}") || default
      end

      define_method("#{name}=") do |value|
        instance_variable_set("@#{name}", value)
      end
    end

    def self.attr_with_validation(name, validator)
      define_method(name) do
        instance_variable_get("@#{name}")
      end

      define_method("#{name}=") do |value|
        raise ArgumentError, "Invalid value for #{name}" unless validator.call(value)
        instance_variable_set("@#{name}", value)
      end
    end
  end

  # method_missing
  class FlexibleStruct
    def initialize(hash = {})
      @attributes = hash.transform_keys(&:to_sym)
    end

    def method_missing(method, *args, &block)
      method_name = method.to_s

      if method_name.end_with?('=')
        @attributes[method_name.chomp('=').to_sym] = args.first
      elsif method_name.end_with?('?')
        !!@attributes[method_name.chomp('?').to_sym]
      else
        @attributes[method.to_sym]
      end
    end

    def respond_to_missing?(method, include_private = false)
      true
    end

    def to_h = @attributes.dup
  end

  # class_eval and instance_eval
  class DynamicClass
    def self.add_greeting(language, message)
      define_method("greet_#{language}") do |name|
        "#{message}, #{name}!"
      end
    end

    def self.add_class_method(name, &block)
      define_singleton_method(name, &block)
    end
  end

  # const_missing
  class AutoloadConstants
    def self.const_missing(name)
      puts "Loading constant: #{name}"
      const_set(name, Class.new)
    end
  end

  # Module building
  def self.create_validation_module(*fields)
    Module.new do
      fields.each do |field|
        define_method("validate_#{field}") do
          value = send(field)
          raise "#{field} cannot be nil" if value.nil?
          raise "#{field} cannot be empty" if value.respond_to?(:empty?) && value.empty?
          true
        end
      end

      define_method(:validate_all) do
        fields.all? { |f| send("validate_#{f}") }
      end
    end
  end

  # Singleton pattern via metaprogramming
  module Singleton
    def self.included(base)
      base.class_eval do
        @instance = nil
        @mutex = Mutex.new

        def self.instance
          return @instance if @instance

          @mutex.synchronize do
            @instance ||= new
          end
        end

        private_class_method :new
      end
    end
  end
end

# ===== Concurrent Programming =====

module ConcurrentProgramming
  # Thread-based concurrency
  class ThreadPool
    def initialize(size: 4)
