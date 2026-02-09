// C++ sample file - Modern C++20/23 patterns with advanced features
// This file demonstrates comprehensive C++ syntax for highlighting tests

#include <iostream>
#include <vector>
#include <algorithm>
#include <memory>
#include <optional>
#include <variant>
#include <string>
#include <string_view>
#include <unordered_map>
#include <map>
#include <set>
#include <functional>
#include <concepts>
#include <coroutine>
#include <span>
#include <ranges>
#include <thread>
#include <mutex>
#include <shared_mutex>
#include <condition_variable>
#include <future>
#include <atomic>
#include <chrono>
#include <format>
#include <source_location>
#include <stacktrace>
#include <expected>
#include <type_traits>
#include <utility>
#include <tuple>
#include <array>
#include <deque>
#include <queue>
#include <stack>
#include <list>
#include <forward_list>
#include <bitset>
#include <numeric>
#include <random>
#include <regex>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <filesystem>

namespace fs = std::filesystem;
using namespace std::chrono_literals;
using namespace std::string_literals;

// ============================================================================
// SECTION 1: Concepts and Constraints
// ============================================================================

// Basic concepts
template<typename T>
concept Printable = requires(T t, std::ostream& os) {
    { os << t } -> std::same_as<std::ostream&>;
};

template<typename T>
concept Hashable = requires(T t) {
    { std::hash<T>{}(t) } -> std::convertible_to<std::size_t>;
};

template<typename T>
concept Serializable = requires(T t) {
    { t.serialize() } -> std::convertible_to<std::string>;
    { T::deserialize(std::declval<std::string_view>()) } -> std::same_as<T>;
};

template<typename T>
concept Cloneable = requires(T t) {
    { t.clone() } -> std::same_as<T>;
};

template<typename T>
concept Numeric = std::is_arithmetic_v<T>;

template<typename T>
concept Container = requires(T t) {
    typename T::value_type;
    typename T::iterator;
    typename T::const_iterator;
    { t.begin() } -> std::same_as<typename T::iterator>;
    { t.end() } -> std::same_as<typename T::iterator>;
    { t.size() } -> std::convertible_to<std::size_t>;
    { t.empty() } -> std::same_as<bool>;
};

template<typename T>
concept Comparable = requires(T a, T b) {
    { a == b } -> std::convertible_to<bool>;
    { a != b } -> std::convertible_to<bool>;
    { a < b } -> std::convertible_to<bool>;
    { a <= b } -> std::convertible_to<bool>;
    { a > b } -> std::convertible_to<bool>;
    { a >= b } -> std::convertible_to<bool>;
};

template<typename F, typename... Args>
concept Callable = std::invocable<F, Args...>;

template<typename F, typename R, typename... Args>
concept CallableReturning = std::invocable<F, Args...> &&
    std::same_as<std::invoke_result_t<F, Args...>, R>;

// Compound concepts
template<typename T>
concept Entity = Printable<T> && Comparable<T> && Cloneable<T>;

// ============================================================================
// SECTION 2: Type Traits and Metaprogramming
// ============================================================================

namespace meta {
    // Type list
    template<typename... Ts>
    struct TypeList {
        static constexpr std::size_t size = sizeof...(Ts);
    };

    // Get type at index
    template<std::size_t I, typename List>
    struct TypeAt;

    template<std::size_t I, typename Head, typename... Tail>
    struct TypeAt<I, TypeList<Head, Tail...>> {
        using type = typename TypeAt<I - 1, TypeList<Tail...>>::type;
    };

    template<typename Head, typename... Tail>
    struct TypeAt<0, TypeList<Head, Tail...>> {
        using type = Head;
    };

    template<std::size_t I, typename List>
    using TypeAt_t = typename TypeAt<I, List>::type;

    // Contains type
    template<typename T, typename List>
    struct Contains;

    template<typename T>
    struct Contains<T, TypeList<>> : std::false_type {};

    template<typename T, typename Head, typename... Tail>
    struct Contains<T, TypeList<Head, Tail...>>
        : std::conditional_t<std::is_same_v<T, Head>,
                             std::true_type,
                             Contains<T, TypeList<Tail...>>> {};

    // Transform type list
    template<template<typename> class F, typename List>
    struct Transform;

    template<template<typename> class F, typename... Ts>
    struct Transform<F, TypeList<Ts...>> {
        using type = TypeList<typename F<Ts>::type...>;
    };

    template<template<typename> class F, typename List>
    using Transform_t = typename Transform<F, List>::type;

    // Filter type list
    template<template<typename> class Pred, typename List>
    struct Filter;

    template<template<typename> class Pred>
    struct Filter<Pred, TypeList<>> {
        using type = TypeList<>;
    };

    // Compile-time string
    template<std::size_t N>
    struct FixedString {
        char data[N]{};
        constexpr FixedString(const char (&str)[N]) {
            std::copy_n(str, N, data);
        }
        constexpr auto operator<=>(const FixedString&) const = default;
    };
}

// ============================================================================
// SECTION 3: Enums and Strong Types
// ============================================================================

enum class Color : uint8_t {
    Red = 0,
    Green = 1,
    Blue = 2,
    Yellow = 3,
    Magenta = 4,
    Cyan = 5,
    White = 7,
    Black = 8
};

constexpr std::string_view color_to_string(Color c) {
    switch (c) {
        case Color::Red:     return "Red";
        case Color::Green:   return "Green";
        case Color::Blue:    return "Blue";
        case Color::Yellow:  return "Yellow";
        case Color::Magenta: return "Magenta";
        case Color::Cyan:    return "Cyan";
        case Color::White:   return "White";
        case Color::Black:   return "Black";
    }
    return "Unknown";
}

enum class LogLevel { Trace, Debug, Info, Warn, Error, Fatal };

template<typename T>
struct StrongType {
    T value;
    explicit constexpr StrongType(T val) : value(std::move(val)) {}
    constexpr T& get() { return value; }
    constexpr const T& get() const { return value; }
    constexpr auto operator<=>(const StrongType&) const = default;
};

using UserId = StrongType<int64_t>;
using Email = StrongType<std::string>;
using Score = StrongType<double>;

// ============================================================================
// SECTION 4: Classes, Inheritance, CRTP
// ============================================================================

class Shape {
public:
    virtual ~Shape() = default;
    virtual double area() const = 0;
    virtual double perimeter() const = 0;
    virtual std::string name() const = 0;
    virtual std::unique_ptr<Shape> clone() const = 0;

    friend std::ostream& operator<<(std::ostream& os, const Shape& s) {
        return os << s.name() << "(area=" << s.area()
                  << ", perimeter=" << s.perimeter() << ")";
    }
};

class Circle final : public Shape {
    double radius_;
public:
    explicit Circle(double r) : radius_(r) {}
    double area() const override { return std::numbers::pi * radius_ * radius_; }
    double perimeter() const override { return 2.0 * std::numbers::pi * radius_; }
    std::string name() const override { return "Circle"; }
    std::unique_ptr<Shape> clone() const override {
        return std::make_unique<Circle>(*this);
    }
    double radius() const { return radius_; }
};

class Rectangle : public Shape {
protected:
    double width_, height_;
public:
    Rectangle(double w, double h) : width_(w), height_(h) {}
    double area() const override { return width_ * height_; }
    double perimeter() const override { return 2.0 * (width_ + height_); }
    std::string name() const override { return "Rectangle"; }
    std::unique_ptr<Shape> clone() const override {
        return std::make_unique<Rectangle>(*this);
    }
};

class Square final : public Rectangle {
public:
    explicit Square(double side) : Rectangle(side, side) {}
    std::string name() const override { return "Square"; }
    std::unique_ptr<Shape> clone() const override {
        return std::make_unique<Square>(*this);
    }
};

// CRTP pattern
template<typename Derived>
class Singleton {
protected:
    Singleton() = default;
    ~Singleton() = default;
    Singleton(const Singleton&) = delete;
    Singleton& operator=(const Singleton&) = delete;
public:
    static Derived& instance() {
        static Derived inst;
        return inst;
    }
};

class AppConfig : public Singleton<AppConfig> {
    friend class Singleton<AppConfig>;
    std::unordered_map<std::string, std::string> settings_;
    AppConfig() = default;
public:
    void set(const std::string& key, const std::string& value) {
        settings_[key] = value;
    }
    std::optional<std::string> get(const std::string& key) const {
        if (auto it = settings_.find(key); it != settings_.end()) {
            return it->second;
        }
        return std::nullopt;
    }
};

// CRTP for operator injection
template<typename Derived>
struct Addable {
    friend Derived operator+(const Derived& a, const Derived& b) {
        Derived result = a;
        result += b;
        return result;
    }
};

struct Vector3D : Addable<Vector3D> {
    double x, y, z;
    constexpr Vector3D(double x = 0, double y = 0, double z = 0)
        : x(x), y(y), z(z) {}
    Vector3D& operator+=(const Vector3D& other) {
        x += other.x; y += other.y; z += other.z;
        return *this;
    }
    constexpr double magnitude() const {
        return std::sqrt(x*x + y*y + z*z);
    }
    constexpr Vector3D normalized() const {
        double m = magnitude();
        return {x/m, y/m, z/m};
    }
    constexpr double dot(const Vector3D& other) const {
        return x*other.x + y*other.y + z*other.z;
    }
    constexpr Vector3D cross(const Vector3D& other) const {
        return {
            y*other.z - z*other.y,
            z*other.x - x*other.z,
            x*other.y - y*other.x
        };
    }
    friend std::ostream& operator<<(std::ostream& os, const Vector3D& v) {
        return os << "(" << v.x << ", " << v.y << ", " << v.z << ")";
    }
    auto operator<=>(const Vector3D&) const = default;
};

// ============================================================================
// SECTION 5: Smart Pointers and RAII
// ============================================================================

class FileHandle {
    std::FILE* handle_;
public:
    explicit FileHandle(const char* path, const char* mode)
        : handle_(std::fopen(path, mode)) {
        if (!handle_) {
            throw std::runtime_error(
                std::format("Failed to open file: {}", path));
        }
    }
    ~FileHandle() {
        if (handle_) std::fclose(handle_);
    }
    FileHandle(const FileHandle&) = delete;
    FileHandle& operator=(const FileHandle&) = delete;
    FileHandle(FileHandle&& other) noexcept : handle_(other.handle_) {
        other.handle_ = nullptr;
    }
    FileHandle& operator=(FileHandle&& other) noexcept {
        if (this != &other) {
            if (handle_) std::fclose(handle_);
            handle_ = other.handle_;
            other.handle_ = nullptr;
        }
        return *this;
    }
    std::FILE* get() const { return handle_; }
    explicit operator bool() const { return handle_ != nullptr; }
};

template<typename T>
class ObjectPool {
    std::vector<std::unique_ptr<T>> pool_;
    std::vector<T*> available_;
    mutable std::mutex mutex_;
public:
    explicit ObjectPool(size_t initial_size = 10) {
        for (size_t i = 0; i < initial_size; ++i) {
            auto obj = std::make_unique<T>();
            available_.push_back(obj.get());
            pool_.push_back(std::move(obj));
        }
    }

    struct Deleter {
        ObjectPool* pool;
        void operator()(T* ptr) const {
            pool->release(ptr);
        }
    };

    using Ptr = std::unique_ptr<T, Deleter>;

    Ptr acquire() {
        std::lock_guard lock(mutex_);
        if (available_.empty()) {
            auto obj = std::make_unique<T>();
            auto* raw = obj.get();
            pool_.push_back(std::move(obj));
            return Ptr(raw, Deleter{this});
        }
        T* ptr = available_.back();
        available_.pop_back();
        return Ptr(ptr, Deleter{this});
    }

    void release(T* ptr) {
        std::lock_guard lock(mutex_);
        available_.push_back(ptr);
    }

    size_t available_count() const {
        std::lock_guard lock(mutex_);
        return available_.size();
    }
};

// ============================================================================
// SECTION 6: Lambda Expressions and Functional Patterns
// ============================================================================

namespace functional {
    // Higher-order functions
    template<typename F>
    auto memoize(F&& f) {
        using ArgType = typename decltype(std::function{f})::argument_type;
        using RetType = typename decltype(std::function{f})::result_type;
        auto cache = std::make_shared<std::unordered_map<ArgType, RetType>>();
        return [cache, f = std::forward<F>(f)](ArgType arg) -> RetType {
            if (auto it = cache->find(arg); it != cache->end()) {
                return it->second;
            }
            auto result = f(arg);
            cache->emplace(arg, result);
            return result;
        };
    }

    template<typename F, typename G>
    auto compose(F&& f, G&& g) {
        return [f = std::forward<F>(f), g = std::forward<G>(g)](auto&&... args) {
            return f(g(std::forward<decltype(args)>(args)...));
        };
    }

    template<typename F, typename... Fs>
    auto pipeline(F&& first, Fs&&... rest) {
        if constexpr (sizeof...(rest) == 0) {
            return std::forward<F>(first);
        } else {
            return compose(
                pipeline(std::forward<Fs>(rest)...),
                std::forward<F>(first)
            );
        }
    }

    // Partial application
    template<typename F, typename... BoundArgs>
    auto partial(F&& f, BoundArgs&&... bound) {
        return [f = std::forward<F>(f),
                ...bound = std::forward<BoundArgs>(bound)]
               (auto&&... args) {
            return f(bound..., std::forward<decltype(args)>(args)...);
        };
    }

    void demo() {
        // Lambda with init capture
        auto counter = [n = 0]() mutable { return ++n; };
        auto c1 = counter(); // 1
        auto c2 = counter(); // 2

        // Generic lambda with concepts
        auto add = []<Numeric T>(T a, T b) { return a + b; };
        auto sum_int = add(3, 4);
        auto sum_dbl = add(3.14, 2.71);

        // Immediately invoked lambda
        const auto config_value = [&]() {
            auto& cfg = AppConfig::instance();
            auto val = cfg.get("threshold");
            return val.value_or("100");
        }();

        // Lambda returning lambda
        auto multiplier = [](double factor) {
            return [factor](double x) { return x * factor; };
        };
        auto double_it = multiplier(2.0);
        auto triple_it = multiplier(3.0);

        // Recursive lambda with Y combinator
        auto fibonacci = [](auto self, int n) -> int {
            if (n <= 1) return n;
            return self(self, n - 1) + self(self, n - 2);
        };
        auto fib10 = fibonacci(fibonacci, 10);

        // Fold expressions with lambdas
        auto print_all = [](auto&&... args) {
            ((std::cout << args << " "), ...);
            std::cout << "\n";
        };
        print_all(1, "hello", 3.14, 'x');
    }
}

// ============================================================================
// SECTION 7: Ranges and Views (C++20)
// ============================================================================

namespace ranges_demo {
    void demonstrate_ranges() {
        std::vector<int> numbers = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};

        // Filter and transform
        auto even_squares = numbers
            | std::views::filter([](int n) { return n % 2 == 0; })
            | std::views::transform([](int n) { return n * n; });

        for (int val : even_squares) {
            std::cout << val << " ";
        }

        // Chained views
        auto result = numbers
            | std::views::drop(2)
            | std::views::take(5)
            | std::views::reverse;

        // iota view
        for (auto i : std::views::iota(1, 20)
                     | std::views::filter([](int n) { return n % 3 == 0; })) {
            std::cout << i << " ";
        }

        // keys and values views with maps
        std::map<std::string, int> scores = {
            {"Alice", 95}, {"Bob", 87}, {"Charlie", 92}
        };
        for (auto& name : scores | std::views::keys) {
            std::cout << name << " ";
        }

        // zip view (C++23)
        std::vector<std::string> names = {"Alpha", "Beta", "Gamma"};
        std::vector<int> ids = {1, 2, 3};
        for (auto [name, id] : std::views::zip(names, ids)) {
            std::cout << id << ": " << name << "\n";
        }
    }
}

// ============================================================================
// SECTION 8: Variant, Visit, and Expected
// ============================================================================

namespace variant_demo {
    using JsonValue = std::variant<
        std::nullptr_t,
        bool,
        int64_t,
        double,
        std::string,
        std::vector<std::variant<std::nullptr_t, bool, int64_t, double, std::string>>,
        std::map<std::string, std::variant<std::nullptr_t, bool, int64_t, double, std::string>>
    >;

    struct JsonPrinter {
        std::string operator()(std::nullptr_t) const { return "null"; }
        std::string operator()(bool b) const { return b ? "true" : "false"; }
        std::string operator()(int64_t i) const { return std::to_string(i); }
        std::string operator()(double d) const { return std::format("{:.6f}", d); }
        std::string operator()(const std::string& s) const {
            return std::format("\"{}\"", s);
        }
        template<typename T>
        std::string operator()(const std::vector<T>& vec) const {
            std::string result = "[";
            for (size_t i = 0; i < vec.size(); ++i) {
                if (i > 0) result += ", ";
                result += std::visit(JsonPrinter{}, vec[i]);
            }
            return result + "]";
        }
        template<typename T>
        std::string operator()(const std::map<std::string, T>& map) const {
            std::string result = "{";
            bool first = true;
            for (auto& [key, val] : map) {
                if (!first) result += ", ";
                first = false;
                result += std::format("\"{}\": {}", key, std::visit(JsonPrinter{}, val));
            }
            return result + "}";
        }
    };

    // Expected for error handling
    enum class ParseError { InvalidSyntax, UnexpectedToken, Overflow };

    std::expected<int, ParseError> parse_int(std::string_view sv) {
        try {
            size_t pos;
            int result = std::stoi(std::string(sv), &pos);
            if (pos != sv.size()) {
                return std::unexpected(ParseError::InvalidSyntax);
            }
            return result;
        } catch (const std::out_of_range&) {
            return std::unexpected(ParseError::Overflow);
        } catch (...) {
            return std::unexpected(ParseError::UnexpectedToken);
        }
    }

    void demo_expected() {
        auto result = parse_int("42");
        if (result) {
            std::cout << "Parsed: " << *result << "\n";
        }

        auto bad = parse_int("abc");
        auto val = bad.value_or(-1);

        // Monadic operations (C++23)
        auto doubled = parse_int("21")
            .transform([](int n) { return n * 2; })
            .transform([](int n) { return std::to_string(n); });
    }
}

// ============================================================================
// SECTION 9: constexpr / consteval
// ============================================================================

consteval int factorial(int n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

constexpr auto compile_time_fact = factorial(10);

template<int N>
consteval auto fibonacci_array() {
    std::array<int, N> fib{};
    fib[0] = 0;
    if constexpr (N > 1) fib[1] = 1;
    for (int i = 2; i < N; ++i) {
        fib[i] = fib[i-1] + fib[i-2];
    }
    return fib;
}

constexpr auto fib_table = fibonacci_array<20>();

constexpr auto is_palindrome(std::string_view sv) -> bool {
    for (std::size_t i = 0; i < sv.size() / 2; ++i) {
        if (sv[i] != sv[sv.size() - 1 - i]) return false;
    }
    return true;
}

static_assert(is_palindrome("racecar"));
static_assert(!is_palindrome("hello"));
static_assert(factorial(5) == 120);

// ============================================================================
// SECTION 10: Thread-Safe Data Structures
// ============================================================================

template<typename T>
class ThreadSafeQueue {
    std::queue<T> queue_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    std::atomic<bool> done_{false};

public:
    void push(T value) {
        {
            std::lock_guard lock(mutex_);
            queue_.push(std::move(value));
        }
        cv_.notify_one();
    }

    std::optional<T> try_pop() {
        std::lock_guard lock(mutex_);
        if (queue_.empty()) return std::nullopt;
        T val = std::move(queue_.front());
        queue_.pop();
        return val;
    }

    T wait_and_pop() {
        std::unique_lock lock(mutex_);
        cv_.wait(lock, [this] { return !queue_.empty() || done_.load(); });
        if (queue_.empty()) throw std::runtime_error("Queue is done");
        T val = std::move(queue_.front());
        queue_.pop();
        return val;
    }

    void shutdown() {
        done_.store(true);
        cv_.notify_all();
    }

    bool empty() const {
        std::lock_guard lock(mutex_);
        return queue_.empty();
    }

    size_t size() const {
        std::lock_guard lock(mutex_);
        return queue_.size();
    }
};

template<typename Key, typename Value>
class ConcurrentMap {
    std::unordered_map<Key, Value> map_;
    mutable std::shared_mutex mutex_;

public:
    void insert(const Key& key, Value value) {
        std::unique_lock lock(mutex_);
        map_[key] = std::move(value);
    }

    std::optional<Value> find(const Key& key) const {
        std::shared_lock lock(mutex_);
        auto it = map_.find(key);
        if (it != map_.end()) return it->second;
        return std::nullopt;
    }

    bool erase(const Key& key) {
        std::unique_lock lock(mutex_);
        return map_.erase(key) > 0;
    }

    size_t size() const {
        std::shared_lock lock(mutex_);
        return map_.size();
    }

    template<typename F>
    void for_each(F&& func) const {
        std::shared_lock lock(mutex_);
        for (const auto& [k, v] : map_) {
            func(k, v);
        }
    }
};

// ============================================================================
// SECTION 11: Structured Bindings and Aggregates
// ============================================================================

struct Point2D {
    double x, y;
    auto operator<=>(const Point2D&) const = default;
};

struct Config {
    std::string host = "localhost";
    int port = 8080;
    bool ssl = false;
    std::chrono::seconds timeout = 30s;
};

void structured_bindings_demo() {
    // With arrays
    int arr[] = {1, 2, 3};
    auto [a, b, c] = arr;

    // With tuples
    auto [name, age, score] = std::tuple{"Alice"s, 30, 95.5};

    // With structs
    Config cfg{.host = "api.example.com", .port = 443, .ssl = true};
    auto& [host, port, ssl, timeout] = cfg;

    // With maps
    std::map<std::string, int> grades = {{"Math", 95}, {"Science", 88}};
    for (const auto& [subject, grade] : grades) {
        std::cout << std::format("{}: {}\n", subject, grade);
    }

    // With optional
    std::optional<std::pair<int, std::string>> maybe_pair =
        std::make_pair(42, "answer"s);
    if (maybe_pair) {
        auto& [num, text] = *maybe_pair;
        std::cout << std::format("{} = {}\n", text, num);
    }
}

// ============================================================================
// SECTION 12: Template Specialization
// ============================================================================

template<typename T>
struct Serializer {
    static std::string serialize(const T& value) {
        std::ostringstream oss;
        oss << value;
        return oss.str();
    }
};

template<>
struct Serializer<bool> {
    static std::string serialize(bool value) {
        return value ? "true" : "false";
    }
};

template<>
struct Serializer<std::string> {
    static std::string serialize(const std::string& value) {
        return "\"" + value + "\"";
    }
};

template<typename T>
struct Serializer<std::vector<T>> {
    static std::string serialize(const std::vector<T>& vec) {
        std::string result = "[";
        for (size_t i = 0; i < vec.size(); ++i) {
            if (i > 0) result += ", ";
            result += Serializer<T>::serialize(vec[i]);
        }
        return result + "]";
    }
};

template<typename K, typename V>
struct Serializer<std::map<K, V>> {
    static std::string serialize(const std::map<K, V>& map) {
        std::string result = "{";
        bool first = true;
        for (const auto& [key, val] : map) {
            if (!first) result += ", ";
            first = false;
            result += Serializer<K>::serialize(key) + ": " +
                      Serializer<V>::serialize(val);
        }
        return result + "}";
    }
};

// ============================================================================
// SECTION 13: Exception Handling
// ============================================================================

class AppException : public std::exception {
    std::string message_;
    std::source_location location_;
public:
    AppException(std::string msg,
                 std::source_location loc = std::source_location::current())
        : message_(std::move(msg)), location_(loc) {}

    const char* what() const noexcept override {
        return message_.c_str();
    }

    std::string full_message() const {
        return std::format("{}:{} in {}: {}",
            location_.file_name(), location_.line(),
            location_.function_name(), message_);
    }
};

class NetworkException : public AppException {
    int error_code_;
public:
    NetworkException(std::string msg, int code)
        : AppException(std::move(msg)), error_code_(code) {}
    int error_code() const { return error_code_; }
};

void exception_demo() {
    try {
        throw NetworkException("Connection refused", 111);
    } catch (const NetworkException& e) {
        std::cerr << "Network error " << e.error_code()
                  << ": " << e.what() << "\n";
    } catch (const AppException& e) {
        std::cerr << e.full_message() << "\n";
    } catch (...) {
        std::cerr << "Unknown exception\n";
        std::rethrow_exception(std::current_exception());
    }
}

// ============================================================================
// SECTION 14: Filesystem Operations
// ============================================================================

namespace fs_demo {
    void scan_directory(const fs::path& dir) {
        if (!fs::exists(dir)) {
            std::cerr << "Directory not found: " << dir << "\n";
            return;
        }

        size_t total_size = 0;
        int file_count = 0;
        std::map<std::string, int> ext_count;

        for (const auto& entry : fs::recursive_directory_iterator(dir)) {
            if (entry.is_regular_file()) {
                ++file_count;
                total_size += entry.file_size();
                auto ext = entry.path().extension().string();
                ext_count[ext]++;
            }
        }

        std::cout << std::format("Directory: {}\n", dir.string());
        std::cout << std::format("Total files: {}\n", file_count);
        std::cout << std::format("Total size: {} bytes\n", total_size);
        std::cout << "Extensions:\n";
        for (const auto& [ext, count] : ext_count) {
            std::cout << std::format("  {}: {} files\n",
                ext.empty() ? "(none)" : ext, count);
        }
    }

    void copy_with_progress(const fs::path& src, const fs::path& dst) {
        auto total_size = fs::file_size(src);
        std::ifstream in(src, std::ios::binary);
        std::ofstream out(dst, std::ios::binary);

        constexpr size_t buffer_size = 8192;
        char buffer[buffer_size];
        size_t copied = 0;

        while (in.read(buffer, buffer_size) || in.gcount() > 0) {
            out.write(buffer, in.gcount());
            copied += in.gcount();
            double progress = 100.0 * copied / total_size;
            std::cout << std::format("\rCopying: {:.1f}%", progress) << std::flush;
        }
        std::cout << "\n";
    }
}

// ============================================================================
// SECTION 15: STL Algorithms
// ============================================================================

void algorithms_demo() {
    std::vector<int> data = {5, 3, 8, 1, 9, 2, 7, 4, 6};

    // Sorting variants
    std::ranges::sort(data);
    std::ranges::sort(data, std::greater{});

    // Stable partition
    auto it = std::stable_partition(data.begin(), data.end(),
        [](int n) { return n % 2 == 0; });

    // Parallel algorithms
    std::vector<double> values(1'000'000);
    std::iota(values.begin(), values.end(), 1.0);

    auto sum = std::reduce(std::execution::par_unseq,
        values.begin(), values.end(), 0.0);

    std::transform(std::execution::par,
        values.begin(), values.end(), values.begin(),
        [](double v) { return std::sqrt(v); });

    // Accumulate with custom op
    auto product = std::accumulate(data.begin(), data.end(), 1,
        std::multiplies<>{});

    // nth_element
    std::vector<int> nums = {9, 4, 7, 2, 5, 8, 1, 3, 6};
    std::nth_element(nums.begin(), nums.begin() + 4, nums.end());
    auto median = nums[4];

    // adjacent_difference
    std::vector<int> seq = {1, 4, 9, 16, 25};
    std::vector<int> diffs;
    std::adjacent_difference(seq.begin(), seq.end(),
        std::back_inserter(diffs));

    // set operations
    std::set<int> set_a = {1, 2, 3, 4, 5};
    std::set<int> set_b = {3, 4, 5, 6, 7};
    std::vector<int> intersection;
    std::set_intersection(set_a.begin(), set_a.end(),
        set_b.begin(), set_b.end(),
        std::back_inserter(intersection));
}

// ============================================================================
// SECTION 16: Coroutines (C++20)
// ============================================================================

template<typename T>
struct Generator {
    struct promise_type {
        T current_value;
        Generator get_return_object() {
            return Generator{std::coroutine_handle<promise_type>::from_promise(*this)};
        }
        std::suspend_always initial_suspend() { return {}; }
        std::suspend_always final_suspend() noexcept { return {}; }
        std::suspend_always yield_value(T value) {
            current_value = std::move(value);
            return {};
        }
        void return_void() {}
        void unhandled_exception() { std::terminate(); }
    };

    std::coroutine_handle<promise_type> handle_;

    explicit Generator(std::coroutine_handle<promise_type> h) : handle_(h) {}
    ~Generator() { if (handle_) handle_.destroy(); }
    Generator(Generator&& other) noexcept : handle_(other.handle_) {
        other.handle_ = nullptr;
    }
    Generator& operator=(Generator&& other) noexcept {
        if (handle_) handle_.destroy();
        handle_ = other.handle_;
        other.handle_ = nullptr;
        return *this;
    }

    struct Iterator {
        std::coroutine_handle<promise_type> handle_;
        bool done_;

        Iterator& operator++() {
            handle_.resume();
            done_ = handle_.done();
            return *this;
        }
        T& operator*() { return handle_.promise().current_value; }
        bool operator!=(const Iterator&) const { return !done_; }
    };

    Iterator begin() {
        handle_.resume();
        return Iterator{handle_, handle_.done()};
    }
    Iterator end() { return Iterator{handle_, true}; }
};

Generator<int> range(int start, int end, int step = 1) {
    for (int i = start; i < end; i += step) {
        co_yield i;
    }
}

Generator<std::pair<int, int>> enumerate_pairs(int n) {
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            co_yield std::pair{i, j};
        }
    }
}

// ============================================================================
// SECTION 17: Operator Overloading and User-Defined Literals
// ============================================================================

class BigInt {
    std::vector<int> digits_;
    bool negative_ = false;
public:
    BigInt() = default;
    explicit BigInt(const std::string& str) {
        if (str.empty()) return;
        size_t start = 0;
        if (str[0] == '-') { negative_ = true; start = 1; }
        for (size_t i = str.size(); i > start; --i) {
            digits_.push_back(str[i-1] - '0');
        }
    }

    BigInt operator+(const BigInt& other) const {
        BigInt result;
        int carry = 0;
        size_t maxLen = std::max(digits_.size(), other.digits_.size());
        for (size_t i = 0; i < maxLen || carry; ++i) {
            int sum = carry;
            if (i < digits_.size()) sum += digits_[i];
            if (i < other.digits_.size()) sum += other.digits_[i];
            result.digits_.push_back(sum % 10);
            carry = sum / 10;
        }
        return result;
    }

    BigInt operator*(const BigInt& other) const {
        BigInt result;
        result.digits_.resize(digits_.size() + other.digits_.size(), 0);
        for (size_t i = 0; i < digits_.size(); ++i) {
            int carry = 0;
            for (size_t j = 0; j < other.digits_.size() || carry; ++j) {
                int64_t cur = result.digits_[i + j] +
                    static_cast<int64_t>(digits_[i]) *
                    (j < other.digits_.size() ? other.digits_[j] : 0) + carry;
                result.digits_[i + j] = cur % 10;
                carry = cur / 10;
            }
        }
        while (result.digits_.size() > 1 && result.digits_.back() == 0)
            result.digits_.pop_back();
        return result;
    }

    friend std::ostream& operator<<(std::ostream& os, const BigInt& bi) {
        if (bi.negative_) os << '-';
        for (auto it = bi.digits_.rbegin(); it != bi.digits_.rend(); ++it) {
            os << *it;
        }
        return os;
    }
};

// User-defined literals
constexpr long double operator""_deg(long double deg) {
    return deg * std::numbers::pi_v<long double> / 180.0L;
}

constexpr unsigned long long operator""_KB(unsigned long long bytes) {
    return bytes * 1024;
}

constexpr unsigned long long operator""_MB(unsigned long long bytes) {
    return bytes * 1024 * 1024;
}

// ============================================================================
// MAIN
// ============================================================================

int main() {
    std::cout << "=== C++ Syntax Highlighting Test ===\n\n";

    // Concepts
    static_assert(Numeric<int>);
    static_assert(Numeric<double>);
    static_assert(!Numeric<std::string>);

    // Shapes
    auto shapes = std::vector<std::unique_ptr<Shape>>{};
    shapes.push_back(std::make_unique<Circle>(5.0));
    shapes.push_back(std::make_unique<Rectangle>(4.0, 6.0));
    shapes.push_back(std::make_unique<Square>(3.0));
    for (const auto& s : shapes) {
        std::cout << *s << "\n";
    }

    // Vector3D
    Vector3D v1{1.0, 2.0, 3.0};
    Vector3D v2{4.0, 5.0, 6.0};
    auto v3 = v1 + v2;
    std::cout << "v1 + v2 = " << v3 << "\n";
    std::cout << "dot = " << v1.dot(v2) << "\n";
    std::cout << "cross = " << v1.cross(v2) << "\n";

    // constexpr
    std::cout << "10! = " << compile_time_fact << "\n";
    std::cout << "fib[10] = " << fib_table[10] << "\n";

    // Structured bindings
    structured_bindings_demo();

    // Lambdas
    functional::demo();

    // Ranges
    ranges_demo::demonstrate_ranges();

    // Expected
    variant_demo::demo_expected();

    // Algorithms
    algorithms_demo();

    // Generator coroutine
    for (auto val : range(0, 10, 2)) {
        std::cout << val << " ";
    }
    std::cout << "\n";

    // Thread-safe queue
    ThreadSafeQueue<int> tsq;
    tsq.push(42);
    auto popped = tsq.try_pop();
    std::cout << "Popped: " << popped.value_or(-1) << "\n";

    // User-defined literals
    auto angle = 90.0_deg;
    auto mem = 64_MB;
    std::cout << std::format("90 deg = {} rad\n", angle);
    std::cout << std::format("64 MB = {} bytes\n", mem);

    // BigInt
    BigInt a("12345678901234567890");
    BigInt b("98765432109876543210");
    std::cout << "a + b = " << (a + b) << "\n";

    // Filesystem
    fs_demo::scan_directory(fs::current_path());

    // Exception handling
    try {
        exception_demo();
    } catch (...) {}

    std::cout << "\n=== Done ===\n";
    return 0;
}
