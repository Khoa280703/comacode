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

    template<typename T, typename List>
    inline constexpr bool Contains_v = Contains<T, List>::value;

    // Transform type list
    template<template<typename> class F, typename List>
    struct Transform;

    template<template<typename> class F, typename... Ts>
    struct Transform<F, TypeList<Ts...>> {
        using type = TypeList<typename F<Ts>::type...>;
    };

    template<template<typename> class F, typename List>
    using Transform_t = typename Transform<F, List>::type;

    // Compile-time string
    template<std::size_t N>
    struct FixedString {
        char data[N]{};

        constexpr FixedString(const char (&str)[N]) {
            std::copy_n(str, N, data);
        }

        constexpr operator std::string_view() const {
            return {data, N - 1};
        }

        constexpr auto operator<=>(const FixedString&) const = default;
    };

    // Compile-time counter
    template<typename Tag, int N = 0>
    struct Counter {
        static constexpr int value = N;
        using next = Counter<Tag, N + 1>;
    };

    // SFINAE helpers
    template<typename T, typename = void>
    struct HasToString : std::false_type {};

    template<typename T>
    struct HasToString<T, std::void_t<decltype(std::declval<T>().to_string())>>
        : std::true_type {};

    template<typename T>
    inline constexpr bool HasToString_v = HasToString<T>::value;

    // Conditional member
    template<bool Condition, typename T>
    struct ConditionalMember {};

    template<typename T>
    struct ConditionalMember<true, T> {
        T value;
    };
}

// ============================================================================
// SECTION 3: Result and Option Types
// ============================================================================

// Option type (like std::optional but with monadic operations)
template<typename T>
class Option {
private:
    std::optional<T> value_;

public:
    Option() = default;
    Option(T value) : value_(std::move(value)) {}
    Option(std::nullopt_t) : value_(std::nullopt) {}

    static Option Some(T value) { return Option(std::move(value)); }
    static Option None() { return Option(); }

    [[nodiscard]] bool is_some() const { return value_.has_value(); }
    [[nodiscard]] bool is_none() const { return !value_.has_value(); }

    [[nodiscard]] T& unwrap() & {
        if (!value_) throw std::runtime_error("Called unwrap on None");
        return *value_;
    }

    [[nodiscard]] const T& unwrap() const& {
        if (!value_) throw std::runtime_error("Called unwrap on None");
        return *value_;
    }

    [[nodiscard]] T unwrap_or(T default_value) const {
        return value_.value_or(std::move(default_value));
    }

    template<typename F>
    [[nodiscard]] T unwrap_or_else(F&& func) const {
        return value_ ? *value_ : std::invoke(std::forward<F>(func));
    }

    template<typename F>
    [[nodiscard]] auto map(F&& func) const -> Option<std::invoke_result_t<F, T>> {
        using U = std::invoke_result_t<F, T>;
        if (value_) {
            return Option<U>::Some(std::invoke(std::forward<F>(func), *value_));
        }
        return Option<U>::None();
    }

    template<typename F>
    [[nodiscard]] auto flat_map(F&& func) const -> std::invoke_result_t<F, T> {
        if (value_) {
            return std::invoke(std::forward<F>(func), *value_);
        }
        return std::invoke_result_t<F, T>::None();
    }

    template<typename F>
    Option<T> filter(F&& predicate) const {
        if (value_ && std::invoke(std::forward<F>(predicate), *value_)) {
            return *this;
        }
        return None();
    }

    template<typename F>
    void if_some(F&& func) const {
        if (value_) {
            std::invoke(std::forward<F>(func), *value_);
        }
    }

    auto operator<=>(const Option&) const = default;
};

// Result type for error handling
template<typename T, typename E = std::string>
class Result {
public:
    using ValueType = T;
    using ErrorType = E;

private:
    std::variant<T, E> data_;
    bool is_ok_;

public:
    Result() = default;

    static Result Ok(T value) {
        Result r;
        r.data_ = std::move(value);
        r.is_ok_ = true;
        return r;
    }

    static Result Err(E error) {
        Result r;
        r.data_ = std::move(error);
        r.is_ok_ = false;
        return r;
    }

    [[nodiscard]] bool is_ok() const noexcept { return is_ok_; }
    [[nodiscard]] bool is_err() const noexcept { return !is_ok_; }

    [[nodiscard]] explicit operator bool() const noexcept { return is_ok_; }

    [[nodiscard]] T& value() & {
        if (!is_ok_) throw std::runtime_error("Called value on Err");
        return std::get<T>(data_);
    }

    [[nodiscard]] const T& value() const& {
        if (!is_ok_) throw std::runtime_error("Called value on Err");
        return std::get<T>(data_);
    }

    [[nodiscard]] T&& value() && {
        if (!is_ok_) throw std::runtime_error("Called value on Err");
        return std::get<T>(std::move(data_));
    }

    [[nodiscard]] E& error() & {
        if (is_ok_) throw std::runtime_error("Called error on Ok");
        return std::get<E>(data_);
    }

    [[nodiscard]] const E& error() const& {
        if (is_ok_) throw std::runtime_error("Called error on Ok");
        return std::get<E>(data_);
    }

    [[nodiscard]] T value_or(T default_value) const {
        return is_ok_ ? std::get<T>(data_) : std::move(default_value);
    }

    template<typename F>
    [[nodiscard]] T value_or_else(F&& func) const {
        return is_ok_ ? std::get<T>(data_) : std::invoke(std::forward<F>(func));
    }

    template<typename F>
    [[nodiscard]] auto map(F&& func) -> Result<std::invoke_result_t<F, T>, E> {
        using U = std::invoke_result_t<F, T>;
        if (is_ok_) {
            return Result<U, E>::Ok(std::invoke(std::forward<F>(func), value()));
        }
        return Result<U, E>::Err(error());
    }

    template<typename F>
    [[nodiscard]] auto map_err(F&& func) -> Result<T, std::invoke_result_t<F, E>> {
        using U = std::invoke_result_t<F, E>;
        if (!is_ok_) {
            return Result<T, U>::Err(std::invoke(std::forward<F>(func), error()));
        }
        return Result<T, U>::Ok(value());
    }

    template<typename F>
    [[nodiscard]] auto flat_map(F&& func) -> std::invoke_result_t<F, T> {
        if (is_ok_) {
            return std::invoke(std::forward<F>(func), value());
        }
        return std::invoke_result_t<F, T>::Err(error());
    }

    template<typename F>
    [[nodiscard]] auto and_then(F&& func) -> std::invoke_result_t<F, T> {
        return flat_map(std::forward<F>(func));
    }

    template<typename F>
    Result<T, E> or_else(F&& func) const {
        if (is_ok_) {
            return *this;
        }
        return std::invoke(std::forward<F>(func), error());
    }

    template<typename OkFunc, typename ErrFunc>
    auto match(OkFunc&& ok_func, ErrFunc&& err_func) const {
        if (is_ok_) {
            return std::invoke(std::forward<OkFunc>(ok_func), std::get<T>(data_));
        }
        return std::invoke(std::forward<ErrFunc>(err_func), std::get<E>(data_));
    }
};

// ============================================================================
// SECTION 4: Smart Pointers and RAII
// ============================================================================

// Custom deleter
template<typename T>
struct ArrayDeleter {
    void operator()(T* ptr) const {
        delete[] ptr;
    }
};

// Resource handle with RAII
template<typename Handle, typename Deleter>
class ResourceHandle {
private:
    Handle handle_;
    Deleter deleter_;
    bool owns_;

public:
    explicit ResourceHandle(Handle handle, Deleter deleter = Deleter{})
        : handle_(handle), deleter_(std::move(deleter)), owns_(true) {}

    ~ResourceHandle() {
        if (owns_) {
            deleter_(handle_);
        }
    }

    // Move only
    ResourceHandle(const ResourceHandle&) = delete;
    ResourceHandle& operator=(const ResourceHandle&) = delete;

    ResourceHandle(ResourceHandle&& other) noexcept
        : handle_(other.handle_), deleter_(std::move(other.deleter_)), owns_(other.owns_) {
        other.owns_ = false;
    }

    ResourceHandle& operator=(ResourceHandle&& other) noexcept {
        if (this != &other) {
            if (owns_) {
                deleter_(handle_);
            }
            handle_ = other.handle_;
            deleter_ = std::move(other.deleter_);
            owns_ = other.owns_;
            other.owns_ = false;
        }
        return *this;
    }

    [[nodiscard]] Handle get() const noexcept { return handle_; }
    [[nodiscard]] Handle release() noexcept {
        owns_ = false;
        return handle_;
    }

    void reset(Handle handle) {
        if (owns_) {
            deleter_(handle_);
        }
        handle_ = handle;
        owns_ = true;
    }

    explicit operator bool() const noexcept { return owns_; }
};

// Intrusive reference counting
class RefCounted {
private:
    mutable std::atomic<int> ref_count_{0};

public:
    virtual ~RefCounted() = default;

    void add_ref() const noexcept {
        ref_count_.fetch_add(1, std::memory_order_relaxed);
    }

    void release() const noexcept {
        if (ref_count_.fetch_sub(1, std::memory_order_acq_rel) == 1) {
            delete this;
        }
    }

    [[nodiscard]] int use_count() const noexcept {
        return ref_count_.load(std::memory_order_relaxed);
    }
};

template<typename T>
class IntrusivePtr {
private:
    T* ptr_;

public:
    IntrusivePtr() noexcept : ptr_(nullptr) {}

    explicit IntrusivePtr(T* ptr) noexcept : ptr_(ptr) {
        if (ptr_) ptr_->add_ref();
    }

    IntrusivePtr(const IntrusivePtr& other) noexcept : ptr_(other.ptr_) {
        if (ptr_) ptr_->add_ref();
    }

    IntrusivePtr(IntrusivePtr&& other) noexcept : ptr_(other.ptr_) {
        other.ptr_ = nullptr;
    }

    ~IntrusivePtr() {
        if (ptr_) ptr_->release();
    }

    IntrusivePtr& operator=(const IntrusivePtr& other) noexcept {
        if (this != &other) {
            if (ptr_) ptr_->release();
            ptr_ = other.ptr_;
            if (ptr_) ptr_->add_ref();
        }
        return *this;
    }

    IntrusivePtr& operator=(IntrusivePtr&& other) noexcept {
        if (this != &other) {
            if (ptr_) ptr_->release();
            ptr_ = other.ptr_;
            other.ptr_ = nullptr;
        }
        return *this;
    }

    T* get() const noexcept { return ptr_; }
    T* operator->() const noexcept { return ptr_; }
    T& operator*() const noexcept { return *ptr_; }
    explicit operator bool() const noexcept { return ptr_ != nullptr; }

    void reset(T* ptr = nullptr) noexcept {
        if (ptr_) ptr_->release();
        ptr_ = ptr;
        if (ptr_) ptr_->add_ref();
    }
};

// ============================================================================
// SECTION 5: Entity System
// ============================================================================

enum class Role { Admin, User, Guest, Moderator, Developer };

inline std::ostream& operator<<(std::ostream& os, Role role) {
    switch (role) {
        case Role::Admin: return os << "Admin";
        case Role::User: return os << "User";
        case Role::Guest: return os << "Guest";
        case Role::Moderator: return os << "Moderator";
        case Role::Developer: return os << "Developer";
    }
    return os;
}

inline std::string_view role_to_string(Role role) {
    switch (role) {
        case Role::Admin: return "Admin";
        case Role::User: return "User";
        case Role::Guest: return "Guest";
        case Role::Moderator: return "Moderator";
        case Role::Developer: return "Developer";
    }
    return "Unknown";
}

struct Permissions {
    bool can_read = true;
    bool can_write = false;
    bool can_delete = false;
    bool can_admin = false;

    static Permissions for_role(Role role) {
        switch (role) {
            case Role::Admin:
                return {true, true, true, true};
            case Role::Moderator:
                return {true, true, true, false};
            case Role::Developer:
                return {true, true, false, false};
            case Role::User:
                return {true, true, false, false};
            case Role::Guest:
                return {true, false, false, false};
        }
        return {};
    }

    auto operator<=>(const Permissions&) const = default;
};

class User {
public:
    int id;
    std::string name;
    std::string email;
    Role role;
    std::unordered_map<std::string, std::string> metadata;
    std::chrono::system_clock::time_point created_at;
    std::optional<std::chrono::system_clock::time_point> updated_at;
    Permissions permissions;

    User(int id, std::string name, std::string email, Role role = Role::User)
        : id(id)
        , name(std::move(name))
        , email(std::move(email))
        , role(role)
        , created_at(std::chrono::system_clock::now())
        , permissions(Permissions::for_role(role)) {}

    // Validation
    [[nodiscard]] Result<bool> validate() const {
        std::vector<std::string> errors;

        if (name.length() < 2) {
            errors.push_back("Name must be at least 2 characters");
        }

        if (name.length() > 100) {
            errors.push_back("Name must be at most 100 characters");
        }

        if (email.find('@') == std::string::npos) {
            errors.push_back("Invalid email format");
        }

        // Email regex validation
        static const std::regex email_regex(
            R"(^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$)"
        );
        if (!std::regex_match(email, email_regex)) {
            errors.push_back("Email format is invalid");
        }

        if (!errors.empty()) {
            std::string combined;
            for (const auto& e : errors) {
                if (!combined.empty()) combined += "; ";
                combined += e;
            }
            return Result<bool>::Err(combined);
        }

        return Result<bool>::Ok(true);
    }

    // Builder-style methods
    [[nodiscard]] User with_name(std::string new_name) const {
        User copy = *this;
        copy.name = std::move(new_name);
        copy.updated_at = std::chrono::system_clock::now();
        return copy;
    }

    [[nodiscard]] User with_email(std::string new_email) const {
        User copy = *this;
        copy.email = std::move(new_email);
        copy.updated_at = std::chrono::system_clock::now();
        return copy;
    }

    [[nodiscard]] User with_role(Role new_role) const {
        User copy = *this;
        copy.role = new_role;
        copy.permissions = Permissions::for_role(new_role);
        copy.updated_at = std::chrono::system_clock::now();
        return copy;
    }

    [[nodiscard]] User with_metadata(std::string key, std::string value) const {
        User copy = *this;
        copy.metadata[std::move(key)] = std::move(value);
        copy.updated_at = std::chrono::system_clock::now();
        return copy;
    }

    // Serialization
    [[nodiscard]] std::string serialize() const {
        std::ostringstream oss;
        oss << "{"
            << "\"id\":" << id << ","
            << "\"name\":\"" << name << "\","
            << "\"email\":\"" << email << "\","
            << "\"role\":\"" << role << "\""
            << "}";
        return oss.str();
    }

    // Clone
    [[nodiscard]] User clone() const {
        return *this;
    }

    // Comparison
    auto operator<=>(const User& other) const {
        return id <=> other.id;
    }

    bool operator==(const User& other) const {
        return id == other.id;
    }

    friend std::ostream& operator<<(std::ostream& os, const User& u) {
        return os << "User{id=" << u.id << ", name=\"" << u.name
                  << "\", email=\"" << u.email << "\", role=" << u.role << "}";
    }
};

// User hash for unordered containers
template<>
struct std::hash<User> {
    std::size_t operator()(const User& u) const noexcept {
        return std::hash<int>{}(u.id);
    }
};

// ============================================================================
// SECTION 6: Repository Pattern
// ============================================================================

template<typename T>
class Repository {
public:
    virtual ~Repository() = default;
    virtual Option<T> find_by_id(int id) = 0;
    virtual std::vector<T> find_all() = 0;
    virtual Result<T> save(T entity) = 0;
    virtual Result<bool> remove(int id) = 0;
    virtual std::size_t count() = 0;
    virtual void clear() = 0;
};

class InMemoryUserRepository : public Repository<User> {
private:
    std::unordered_map<int, User> storage_;
    mutable std::shared_mutex mutex_;
    std::atomic<int> next_id_{1};

public:
    Option<User> find_by_id(int id) override {
        std::shared_lock lock(mutex_);
        auto it = storage_.find(id);
        if (it != storage_.end()) {
            return Option<User>::Some(it->second);
        }
        return Option<User>::None();
    }

    std::vector<User> find_all() override {
        std::shared_lock lock(mutex_);
        std::vector<User> users;
        users.reserve(storage_.size());
        for (const auto& [id, user] : storage_) {
            users.push_back(user);
        }
        return users;
    }

    Result<User> save(User user) override {
        auto validation = user.validate();
        if (validation.is_err()) {
            return Result<User>::Err(validation.error());
        }

        std::unique_lock lock(mutex_);

        if (user.id == 0) {
            user.id = next_id_.fetch_add(1);
        }

        storage_.insert_or_assign(user.id, user);
        return Result<User>::Ok(user);
    }

    Result<bool> remove(int id) override {
        std::unique_lock lock(mutex_);
        auto erased = storage_.erase(id);
        if (erased == 0) {
            return Result<bool>::Err("User not found: " + std::to_string(id));
        }
        return Result<bool>::Ok(true);
    }

    std::size_t count() override {
        std::shared_lock lock(mutex_);
        return storage_.size();
    }

    void clear() override {
        std::unique_lock lock(mutex_);
        storage_.clear();
    }

    // Additional query methods
    std::vector<User> find_by_role(Role role) {
        std::shared_lock lock(mutex_);
        std::vector<User> result;
        for (const auto& [id, user] : storage_) {
            if (user.role == role) {
                result.push_back(user);
            }
        }
        return result;
    }

    Option<User> find_by_email(std::string_view email) {
        std::shared_lock lock(mutex_);
        for (const auto& [id, user] : storage_) {
            if (user.email == email) {
                return Option<User>::Some(user);
            }
        }
        return Option<User>::None();
    }

    std::vector<User> find_by_predicate(std::function<bool(const User&)> predicate) {
        std::shared_lock lock(mutex_);
        std::vector<User> result;
        for (const auto& [id, user] : storage_) {
            if (predicate(user)) {
                result.push_back(user);
            }
        }
        return result;
    }
};

// ============================================================================
// SECTION 7: Event System
// ============================================================================

enum class EventType { Created, Updated, Deleted, Accessed, Validated };

inline std::ostream& operator<<(std::ostream& os, EventType type) {
    switch (type) {
        case EventType::Created: return os << "Created";
        case EventType::Updated: return os << "Updated";
        case EventType::Deleted: return os << "Deleted";
        case EventType::Accessed: return os << "Accessed";
        case EventType::Validated: return os << "Validated";
    }
    return os;
}

struct UserEvent {
    EventType type;
    std::variant<User, int> payload;
    std::chrono::system_clock::time_point timestamp;
    std::string source;

    static UserEvent created(User user, std::string source = "system") {
        return {EventType::Created, std::move(user),
                std::chrono::system_clock::now(), std::move(source)};
    }

    static UserEvent updated(User user, std::string source = "system") {
        return {EventType::Updated, std::move(user),
                std::chrono::system_clock::now(), std::move(source)};
    }

    static UserEvent deleted(int id, std::string source = "system") {
        return {EventType::Deleted, id,
                std::chrono::system_clock::now(), std::move(source)};
    }

    static UserEvent accessed(User user, std::string source = "system") {
        return {EventType::Accessed, std::move(user),
                std::chrono::system_clock::now(), std::move(source)};
    }
};

class EventBus {
public:
    using Handler = std::function<void(const UserEvent&)>;
    using HandlerId = std::size_t;

private:
    std::unordered_map<HandlerId, Handler> handlers_;
    mutable std::shared_mutex mutex_;
    std::atomic<HandlerId> next_id_{0};
    std::queue<UserEvent> event_queue_;
    std::condition_variable_any cv_;
    std::atomic<bool> running_{true};
    std::optional<std::jthread> worker_;

public:
    EventBus() {
        // Start async event processor
        worker_ = std::jthread([this](std::stop_token stop_token) {
            while (!stop_token.stop_requested()) {
                UserEvent event;
                {
                    std::unique_lock lock(mutex_);
                    cv_.wait(lock, stop_token, [this] {
                        return !event_queue_.empty() || !running_;
                    });

                    if (stop_token.stop_requested() || !running_) break;
                    if (event_queue_.empty()) continue;

                    event = std::move(event_queue_.front());
                    event_queue_.pop();
                }

                // Process event outside lock
                process_event(event);
            }
        });
    }

    ~EventBus() {
        running_ = false;
        cv_.notify_all();
    }

    HandlerId subscribe(Handler handler) {
        std::unique_lock lock(mutex_);
        auto id = next_id_.fetch_add(1);
        handlers_[id] = std::move(handler);
        return id;
    }

    void unsubscribe(HandlerId id) {
        std::unique_lock lock(mutex_);
        handlers_.erase(id);
    }

    void publish(UserEvent event) {
        {
            std::unique_lock lock(mutex_);
            event_queue_.push(std::move(event));
        }
        cv_.notify_one();
    }

    void publish_sync(const UserEvent& event) {
        process_event(event);
    }

private:
    void process_event(const UserEvent& event) {
        std::shared_lock lock(mutex_);
        for (const auto& [id, handler] : handlers_) {
            try {
                handler(event);
            } catch (const std::exception& e) {
                std::cerr << "Error in event handler " << id << ": "
                          << e.what() << std::endl;
            }
        }
    }
};

// ============================================================================
// SECTION 8: Service Layer
// ============================================================================

class UserService {
private:
    std::shared_ptr<Repository<User>> repository_;
    std::shared_ptr<EventBus> event_bus_;
    mutable std::unordered_map<int, User> cache_;
    mutable std::shared_mutex cache_mutex_;
    std::atomic<std::size_t> cache_hits_{0};
    std::atomic<std::size_t> cache_misses_{0};

public:
    UserService(std::shared_ptr<Repository<User>> repo,
                std::shared_ptr<EventBus> bus)
        : repository_(std::move(repo)), event_bus_(std::move(bus)) {}

    Result<User> find_by_id(int id) {
        // Check cache first
        {
            std::shared_lock lock(cache_mutex_);
            auto it = cache_.find(id);
            if (it != cache_.end()) {
                cache_hits_.fetch_add(1);
                return Result<User>::Ok(it->second);
            }
        }

        cache_misses_.fetch_add(1);

        // Fetch from repository
        auto user_opt = repository_->find_by_id(id);
        if (user_opt.is_none()) {
            return Result<User>::Err("User not found: " + std::to_string(id));
        }

        auto user = user_opt.unwrap();

        // Update cache
        {
            std::unique_lock lock(cache_mutex_);
            cache_[id] = user;
        }

        event_bus_->publish(UserEvent::accessed(user));
        return Result<User>::Ok(user);
    }

    std::vector<User> find_all() {
        return repository_->find_all();
    }

    Result<User> create_user(User user) {
        auto result = repository_->save(std::move(user));
        if (result.is_ok()) {
            auto saved = result.value();
            {
                std::unique_lock lock(cache_mutex_);
                cache_[saved.id] = saved;
            }
            event_bus_->publish(UserEvent::created(saved));
        }
        return result;
    }

    Result<User> update_user(User user) {
        auto result = repository_->save(std::move(user));
        if (result.is_ok()) {
            auto saved = result.value();
            {
                std::unique_lock lock(cache_mutex_);
                cache_[saved.id] = saved;
            }
            event_bus_->publish(UserEvent::updated(saved));
        }
        return result;
    }

    Result<bool> delete_user(int id) {
        auto result = repository_->remove(id);
        if (result.is_ok()) {
            {
                std::unique_lock lock(cache_mutex_);
                cache_.erase(id);
            }
            event_bus_->publish(UserEvent::deleted(id));
        }
        return result;
    }

    void clear_cache() {
        std::unique_lock lock(cache_mutex_);
        cache_.clear();
        cache_hits_ = 0;
        cache_misses_ = 0;
    }

    struct CacheStats {
        std::size_t hits;
        std::size_t misses;
        std::size_t size;
        double hit_rate;
    };

    CacheStats get_cache_stats() const {
        std::shared_lock lock(cache_mutex_);
        auto hits = cache_hits_.load();
        auto misses = cache_misses_.load();
        auto total = hits + misses;
        return {
            hits,
            misses,
            cache_.size(),
            total > 0 ? static_cast<double>(hits) / total : 0.0
        };
    }
};

// ============================================================================
// SECTION 9: Coroutines (C++20)
// ============================================================================

template<typename T>
struct Generator {
    struct promise_type {
        T current_value;
        std::exception_ptr exception;

        Generator get_return_object() {
            return Generator{std::coroutine_handle<promise_type>::from_promise(*this)};
        }

        std::suspend_always initial_suspend() noexcept { return {}; }
        std::suspend_always final_suspend() noexcept { return {}; }

        std::suspend_always yield_value(T value) {
            current_value = std::move(value);
            return {};
        }

        void return_void() {}

        void unhandled_exception() {
            exception = std::current_exception();
        }
    };

    std::coroutine_handle<promise_type> handle;

    explicit Generator(std::coroutine_handle<promise_type> h) : handle(h) {}

    ~Generator() {
        if (handle) handle.destroy();
    }

    Generator(const Generator&) = delete;
    Generator& operator=(const Generator&) = delete;

    Generator(Generator&& other) noexcept : handle(other.handle) {
        other.handle = nullptr;
    }

    Generator& operator=(Generator&& other) noexcept {
        if (this != &other) {
            if (handle) handle.destroy();
            handle = other.handle;
            other.handle = nullptr;
        }
        return *this;
    }

    class Iterator {
    public:
        using iterator_category = std::input_iterator_tag;
        using value_type = T;
        using difference_type = std::ptrdiff_t;
        using pointer = T*;
        using reference = T&;

        std::coroutine_handle<promise_type> handle;

        Iterator() : handle(nullptr) {}
        explicit Iterator(std::coroutine_handle<promise_type> h) : handle(h) {}

        Iterator& operator++() {
            handle.resume();
            if (handle.done()) {
                handle = nullptr;
            }
            return *this;
        }

        T& operator*() { return handle.promise().current_value; }
        T* operator->() { return &handle.promise().current_value; }

        bool operator==(const Iterator& other) const {
            return handle == other.handle;
        }
    };

    Iterator begin() {
        if (handle) {
            handle.resume();
            if (handle.done()) return end();
        }
        return Iterator{handle};
    }

    Iterator end() { return Iterator{}; }
};

// Fibonacci generator using coroutines
Generator<int> fibonacci(int n) {
    int a = 0, b = 1;
    for (int i = 0; i < n; ++i) {
        co_yield a;
        auto next = a + b;
        a = b;
        b = next;
    }
}

// Range generator
Generator<int> range(int start, int end, int step = 1) {
    for (int i = start; i < end; i += step) {
        co_yield i;
    }
}

// ============================================================================
// SECTION 10: Functional Utilities
// ============================================================================

namespace functional {
    // Function composition
    template<typename F, typename G>
    auto compose(F&& f, G&& g) {
        return [f = std::forward<F>(f), g = std::forward<G>(g)]
               (auto&&... args) {
            return g(f(std::forward<decltype(args)>(args)...));
        };
    }

    // Pipe operator
    template<typename T, typename F>
    auto operator|(T&& value, F&& func)
        -> decltype(func(std::forward<T>(value))) {
        return func(std::forward<T>(value));
    }

    // Curry
    template<typename F>
    auto curry(F&& f) {
        return [f = std::forward<F>(f)](auto&& x) {
            return [f, x = std::forward<decltype(x)>(x)](auto&&... args) {
                return f(x, std::forward<decltype(args)>(args)...);
            };
        };
    }

    // Partial application
    template<typename F, typename... Args>
    auto partial(F&& f, Args&&... args) {
        return [f = std::forward<F>(f),
                ...bound = std::forward<Args>(args)]
               (auto&&... rest) {
            return f(bound..., std::forward<decltype(rest)>(rest)...);
        };
    }

    // Memoization
    template<typename F>
    auto memoize(F&& f) {
        using ArgType = typename std::decay_t<F>::argument_type;
        using ReturnType = std::invoke_result_t<F, ArgType>;

        auto cache = std::make_shared<std::unordered_map<ArgType, ReturnType>>();
        auto mutex = std::make_shared<std::mutex>();

        return [f = std::forward<F>(f), cache, mutex](ArgType arg) {
            {
                std::lock_guard lock(*mutex);
                auto it = cache->find(arg);
                if (it != cache->end()) {
                    return it->second;
                }
            }

            auto result = f(arg);

            {
                std::lock_guard lock(*mutex);
                (*cache)[arg] = result;
            }

            return result;
        };
    }

    // Retry with exponential backoff
    template<typename F>
    auto retry(F&& func, int max_attempts = 3,
               std::chrono::milliseconds initial_delay = 100ms) {
        using ReturnType = decltype(func());

        auto current_delay = initial_delay;

        for (int attempt = 0; attempt < max_attempts - 1; ++attempt) {
            try {
                return func();
            } catch (const std::exception& e) {
                std::cerr << "Attempt " << (attempt + 1) << " failed: "
                          << e.what() << std::endl;
                std::this_thread::sleep_for(current_delay);
                current_delay *= 2;
            }
        }

        return func();  // Last attempt
    }

    // Map over container
    template<Container C, typename F>
    auto map(const C& container, F&& func) {
        using T = typename C::value_type;
        using U = std::invoke_result_t<F, T>;

        std::vector<U> result;
        result.reserve(container.size());

        for (const auto& elem : container) {
            result.push_back(std::invoke(func, elem));
        }

        return result;
    }

    // Filter container
    template<Container C, typename F>
    auto filter(const C& container, F&& predicate) {
        using T = typename C::value_type;

        std::vector<T> result;

        for (const auto& elem : container) {
            if (std::invoke(predicate, elem)) {
                result.push_back(elem);
            }
        }

        return result;
    }

    // Reduce/fold
    template<Container C, typename T, typename F>
    T reduce(const C& container, T initial, F&& func) {
        T accumulator = std::move(initial);

        for (const auto& elem : container) {
            accumulator = std::invoke(func, std::move(accumulator), elem);
        }

        return accumulator;
    }

    // Zip two containers
    template<Container C1, Container C2>
    auto zip(const C1& c1, const C2& c2) {
        using T1 = typename C1::value_type;
        using T2 = typename C2::value_type;

        std::vector<std::pair<T1, T2>> result;
        auto it1 = c1.begin();
        auto it2 = c2.begin();

        while (it1 != c1.end() && it2 != c2.end()) {
            result.emplace_back(*it1++, *it2++);
        }

        return result;
    }
}

// ============================================================================
// SECTION 11: Thread Pool
// ============================================================================

class ThreadPool {
private:
    std::vector<std::jthread> workers_;
    std::queue<std::function<void()>> tasks_;
    std::mutex mutex_;
    std::condition_variable cv_;
    std::atomic<bool> stop_{false};
    std::atomic<std::size_t> active_tasks_{0};

public:
    explicit ThreadPool(std::size_t num_threads = std::thread::hardware_concurrency()) {
        for (std::size_t i = 0; i < num_threads; ++i) {
            workers_.emplace_back([this](std::stop_token stop_token) {
                while (!stop_token.stop_requested()) {
                    std::function<void()> task;

                    {
                        std::unique_lock lock(mutex_);
                        cv_.wait(lock, [this, &stop_token] {
                            return stop_token.stop_requested() ||
                                   !tasks_.empty();
                        });

                        if (stop_token.stop_requested() && tasks_.empty()) {
                            return;
                        }

                        if (tasks_.empty()) continue;

                        task = std::move(tasks_.front());
                        tasks_.pop();
                        active_tasks_.fetch_add(1);
                    }

                    try {
                        task();
                    } catch (const std::exception& e) {
                        std::cerr << "Task exception: " << e.what() << std::endl;
                    }

                    active_tasks_.fetch_sub(1);
                }
            });
        }
    }

    ~ThreadPool() {
        stop_ = true;
        cv_.notify_all();
    }

    template<typename F, typename... Args>
    auto enqueue(F&& f, Args&&... args)
        -> std::future<std::invoke_result_t<F, Args...>> {

        using return_type = std::invoke_result_t<F, Args...>;

        auto task = std::make_shared<std::packaged_task<return_type()>>(
            std::bind(std::forward<F>(f), std::forward<Args>(args)...)
        );

        std::future<return_type> result = task->get_future();

        {
            std::lock_guard lock(mutex_);
            if (stop_) {
                throw std::runtime_error("ThreadPool is stopped");
            }
            tasks_.emplace([task]() { (*task)(); });
        }

        cv_.notify_one();
        return result;
    }

    void wait_all() {
        while (active_tasks_.load() > 0 || !tasks_.empty()) {
            std::this_thread::yield();
        }
    }

    std::size_t size() const { return workers_.size(); }
    std::size_t pending() const { return tasks_.size(); }
    std::size_t active() const { return active_tasks_.load(); }
};

// ============================================================================
// SECTION 12: Logging System
// ============================================================================

enum class LogLevel { Trace, Debug, Info, Warning, Error, Fatal };

inline std::ostream& operator<<(std::ostream& os, LogLevel level) {
    switch (level) {
        case LogLevel::Trace: return os << "TRACE";
        case LogLevel::Debug: return os << "DEBUG";
        case LogLevel::Info: return os << "INFO";
        case LogLevel::Warning: return os << "WARN";
        case LogLevel::Error: return os << "ERROR";
        case LogLevel::Fatal: return os << "FATAL";
    }
    return os;
}

class Logger {
private:
    std::string name_;
    LogLevel min_level_;
    std::ostream& output_;
    mutable std::mutex mutex_;

    static std::string current_time() {
        auto now = std::chrono::system_clock::now();
        auto time = std::chrono::system_clock::to_time_t(now);
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            now.time_since_epoch()) % 1000;

        std::ostringstream oss;
        oss << std::put_time(std::localtime(&time), "%Y-%m-%d %H:%M:%S")
            << '.' << std::setfill('0') << std::setw(3) << ms.count();
        return oss.str();
    }

public:
    Logger(std::string name, LogLevel min_level = LogLevel::Info,
           std::ostream& output = std::cout)
        : name_(std::move(name)), min_level_(min_level), output_(output) {}

    template<typename... Args>
    void log(LogLevel level, std::format_string<Args...> fmt, Args&&... args) {
        if (level < min_level_) return;

        auto message = std::format(fmt, std::forward<Args>(args)...);

        std::lock_guard lock(mutex_);
        output_ << "[" << current_time() << "] "
                << "[" << level << "] "
                << "[" << name_ << "] "
                << message << std::endl;
    }

    template<typename... Args>
    void trace(std::format_string<Args...> fmt, Args&&... args) {
        log(LogLevel::Trace, fmt, std::forward<Args>(args)...);
    }

    template<typename... Args>
    void debug(std::format_string<Args...> fmt, Args&&... args) {
        log(LogLevel::Debug, fmt, std::forward<Args>(args)...);
    }

    template<typename... Args>
    void info(std::format_string<Args...> fmt, Args&&... args) {
        log(LogLevel::Info, fmt, std::forward<Args>(args)...);
    }

    template<typename... Args>
    void warning(std::format_string<Args...> fmt, Args&&... args) {
        log(LogLevel::Warning, fmt, std::forward<Args>(args)...);
    }

    template<typename... Args>
    void error(std::format_string<Args...> fmt, Args&&... args) {
        log(LogLevel::Error, fmt, std::forward<Args>(args)...);
    }

    template<typename... Args>
    void fatal(std::format_string<Args...> fmt, Args&&... args) {
        log(LogLevel::Fatal, fmt, std::forward<Args>(args)...);
    }

    void set_level(LogLevel level) { min_level_ = level; }
    LogLevel get_level() const { return min_level_; }
};

// ============================================================================
// MAIN FUNCTION
// ============================================================================

int main() {
    Logger logger("main", LogLevel::Debug);
    logger.info("Starting application...");

    // Create infrastructure
    auto repository = std::make_shared<InMemoryUserRepository>();
    auto event_bus = std::make_shared<EventBus>();
    UserService service(repository, event_bus);

    // Subscribe to events
    event_bus->subscribe([&logger](const UserEvent& event) {
        std::visit([&](auto&& payload) {
            using T = std::decay_t<decltype(payload)>;
            if constexpr (std::is_same_v<T, User>) {
                logger.info("Event {}: User {}", event.type, payload.name);
            } else {
                logger.info("Event {}: ID {}", event.type, payload);
            }
        }, event.payload);
    });

    // Create users
    logger.info("Creating users...");
    service.create_user(User(1, "Alice", "alice@example.com", Role::Admin));
    service.create_user(User(2, "Bob", "bob@example.com", Role::User));
    service.create_user(User(3, "Charlie", "charlie@example.com", Role::Guest));
    service.create_user(User(4, "Diana", "diana@example.com", Role::Developer));
    service.create_user(User(5, "Eve", "eve@example.com", Role::Moderator));

    // Query users
    auto users = service.find_all();
    logger.info("Total users: {}", users.size());

    // Filter with ranges (C++20)
    auto admins = users | std::views::filter([](const User& u) {
        return u.role == Role::Admin;
    });

    logger.info("Admins:");
    for (const auto& admin : admins) {
        logger.info("  - {}", admin.name);
    }

    // Use functional utilities
    auto names = functional::map(users, [](const User& u) { return u.name; });
    logger.info("User names: {}", names.size());

    // Thread pool demo
    ThreadPool pool(4);
    std::vector<std::future<int>> futures;

    for (int i = 0; i < 10; ++i) {
        futures.push_back(pool.enqueue([i] {
            std::this_thread::sleep_for(50ms);
            return i * i;
        }));
    }

    logger.info("Waiting for thread pool tasks...");
    for (auto& f : futures) {
        logger.debug("Result: {}", f.get());
    }

    // Generator demo
    logger.info("Fibonacci sequence:");
    for (auto fib : fibonacci(10)) {
        std::cout << fib << " ";
    }
    std::cout << std::endl;

    // Cache stats
    auto stats = service.get_cache_stats();
    logger.info("Cache stats - hits: {}, misses: {}, size: {}, hit rate: {:.2f}%",
                stats.hits, stats.misses, stats.size, stats.hit_rate * 100);

    logger.info("Application finished successfully!");
    return 0;
}

