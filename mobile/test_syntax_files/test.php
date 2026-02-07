<?php
// PHP sample file - Modern PHP 8.x patterns

declare(strict_types=1);

namespace App;

use InvalidArgumentException;
use RuntimeException;
use DateTime;
use DateTimeImmutable;
use JsonSerializable;
use Stringable;

// ===== Result Type =====

/**
 * @template T
 */
readonly class Result implements JsonSerializable
{
    private function __construct(
        private mixed $value = null,
        private ?string $error = null,
        private bool $isSuccess = true
    ) {}

    /**
     * @template U
     * @param U $value
     * @return Result<U>
     */
    public static function ok(mixed $value): self
    {
        return new self(value: $value, isSuccess: true);
    }

    public static function err(string $error): self
    {
        return new self(error: $error, isSuccess: false);
    }

    public function isOk(): bool
    {
        return $this->isSuccess;
    }

    public function isErr(): bool
    {
        return !$this->isSuccess;
    }

    public function getValue(): mixed
    {
        if (!$this->isSuccess) {
            throw new RuntimeException("Cannot get value from error result: {$this->error}");
        }
        return $this->value;
    }

    public function getError(): ?string
    {
        return $this->error;
    }

    public function getOrDefault(mixed $default): mixed
    {
        return $this->isSuccess ? $this->value : $default;
    }

    /**
     * @template U
     * @param callable(T): U $mapper
     * @return Result<U>
     */
    public function map(callable $mapper): self
    {
        if ($this->isSuccess) {
            return self::ok($mapper($this->value));
        }
        return self::err($this->error);
    }

    /**
     * @template U
     * @param callable(T): Result<U> $mapper
     * @return Result<U>
     */
    public function flatMap(callable $mapper): self
    {
        if ($this->isSuccess) {
            return $mapper($this->value);
        }
        return self::err($this->error);
    }

    public function jsonSerialize(): array
    {
        return $this->isSuccess
            ? ['success' => true, 'data' => $this->value]
            : ['success' => false, 'error' => $this->error];
    }
}

// ===== Enums =====

enum Role: string
{
    case Admin = 'admin';
    case User = 'user';
    case Guest = 'guest';

    public function canModify(): bool
    {
        return match($this) {
            self::Admin, self::User => true,
            self::Guest => false,
        };
    }

    public function canDelete(): bool
    {
        return $this === self::Admin;
    }

    public function permissions(): array
    {
        return match($this) {
            self::Admin => ['read', 'write', 'delete', 'admin'],
            self::User => ['read', 'write'],
            self::Guest => ['read'],
        };
    }
}

// ===== User Entity =====

readonly class User implements JsonSerializable, Stringable
{
    public function __construct(
        public int $id,
        public string $name,
        public string $email,
        public Role $role = Role::User,
        public array $metadata = [],
        public DateTimeImmutable $createdAt = new DateTimeImmutable(),
        public ?DateTimeImmutable $updatedAt = null
    ) {
        if (strlen($name) < 2) {
            throw new InvalidArgumentException("Name must be at least 2 characters");
        }
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new InvalidArgumentException("Invalid email format");
        }
    }

    public function validate(): Result
    {
        $errors = [];

        if (empty(trim($this->name))) {
            $errors[] = "Name cannot be blank";
        }

        if (!preg_match('/^[\w.-]+@[\w.-]+\.\w+$/', $this->email)) {
            $errors[] = "Invalid email format";
        }

        if (!empty($errors)) {
            return Result::err(implode(', ', $errors));
        }

        return Result::ok(true);
    }

    public function withName(string $name): self
    {
        return new self(
            $this->id,
            $name,
            $this->email,
            $this->role,
            $this->metadata,
            $this->createdAt,
            new DateTimeImmutable()
        );
    }

    public function withRole(Role $role): self
    {
        return new self(
            $this->id,
            $this->name,
            $this->email,
            $role,
            $this->metadata,
            $this->createdAt,
            new DateTimeImmutable()
        );
    }

    public function jsonSerialize(): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'email' => $this->email,
            'role' => $this->role->value,
            'metadata' => $this->metadata,
            'createdAt' => $this->createdAt->format(DateTime::ATOM),
            'updatedAt' => $this->updatedAt?->format(DateTime::ATOM),
        ];
    }

    public function __toString(): string
    {
        return "User(id={$this->id}, name=\"{$this->name}\", email=\"{$this->email}\", role={$this->role->value})";
    }
}

// ===== Repository Interface =====

/**
 * @template T
 * @template TId
 */
interface Repository
{
    public function findById(mixed $id): ?object;
    public function findAll(): array;
    public function save(object $entity): Result;
    public function delete(mixed $id): Result;
}

// ===== In-Memory Repository =====

class InMemoryUserRepository implements Repository
{
    /** @var array<int, User> */
    private array $storage = [];

    public function findById(mixed $id): ?User
    {
        return $this->storage[$id] ?? null;
    }

    public function findAll(): array
    {
        return array_values($this->storage);
    }

    public function save(object $entity): Result
    {
        if (!$entity instanceof User) {
            return Result::err("Expected User instance");
        }

        $validation = $entity->validate();
        if ($validation->isErr()) {
            return $validation;
        }

        $this->storage[$entity->id] = $entity;
        return Result::ok($entity);
    }

    public function delete(mixed $id): Result
    {
        if (!isset($this->storage[$id])) {
            return Result::err("User not found: $id");
        }

        unset($this->storage[$id]);
        return Result::ok(true);
    }

    public function findByRole(Role $role): array
    {
        return array_filter(
            $this->storage,
            fn(User $u) => $u->role === $role
        );
    }

    public function findByEmail(string $email): ?User
    {
        foreach ($this->storage as $user) {
            if ($user->email === $email) {
                return $user;
            }
        }
        return null;
    }
}

// ===== Event System =====

enum UserEventType: string
{
    case Created = 'user.created';
    case Updated = 'user.updated';
    case Deleted = 'user.deleted';
}

readonly class UserEvent implements JsonSerializable
{
    public function __construct(
        public UserEventType $type,
        public mixed $payload,
        public DateTimeImmutable $timestamp = new DateTimeImmutable()
    ) {}

    public static function created(User $user): self
    {
        return new self(UserEventType::Created, $user);
    }

    public static function updated(User $user): self
    {
        return new self(UserEventType::Updated, $user);
    }

    public static function deleted(int $id): self
    {
        return new self(UserEventType::Deleted, $id);
    }

    public function jsonSerialize(): array
    {
        return [
            'type' => $this->type->value,
            'payload' => $this->payload,
            'timestamp' => $this->timestamp->format(DateTime::ATOM),
        ];
    }
}

class EventBus
{
    /** @var array<string, array<callable>> */
    private array $subscribers = [];

    public function subscribe(UserEventType $type, callable $handler): void
    {
        $this->subscribers[$type->value][] = $handler;
    }

    public function publish(UserEvent $event): void
    {
        $handlers = $this->subscribers[$event->type->value] ?? [];
        foreach ($handlers as $handler) {
            try {
                $handler($event);
            } catch (\Throwable $e) {
                error_log("Error in event handler: " . $e->getMessage());
            }
        }
    }
}

// ===== Service Layer =====

class UserService
{
    /** @var array<int, User> */
    private array $cache = [];

    public function __construct(
        private readonly Repository $repository,
        private readonly EventBus $eventBus
    ) {}

    public function findById(int $id): Result
    {
        if (isset($this->cache[$id])) {
            return Result::ok($this->cache[$id]);
        }

        $user = $this->repository->findById($id);
        if ($user === null) {
            return Result::err("User not found: $id");
        }

        $this->cache[$id] = $user;
        return Result::ok($user);
    }

    public function findAll(): array
    {
        return $this->repository->findAll();
    }

    public function createUser(User $user): Result
    {
        $result = $this->repository->save($user);
        if ($result->isOk()) {
            $this->cache[$user->id] = $result->getValue();
            $this->eventBus->publish(UserEvent::created($result->getValue()));
        }
        return $result;
    }

    public function updateUser(User $user): Result
    {
        $result = $this->repository->save($user);
        if ($result->isOk()) {
            $this->cache[$user->id] = $result->getValue();
            $this->eventBus->publish(UserEvent::updated($result->getValue()));
        }
        return $result;
    }

    public function deleteUser(int $id): Result
    {
        $result = $this->repository->delete($id);
        if ($result->isOk()) {
            unset($this->cache[$id]);
            $this->eventBus->publish(UserEvent::deleted($id));
        }
        return $result;
    }

    public function clearCache(): void
    {
        $this->cache = [];
    }
}

// ===== Utility Functions =====

function array_filter_by_role(array $users, Role $role): array
{
    return array_filter($users, fn(User $u) => $u->role === $role);
}

function array_sort_by_name(array $users): array
{
    usort($users, fn(User $a, User $b) => strcmp($a->name, $b->name));
    return $users;
}

function retry(callable $action, int $maxAttempts = 3, int $delayMs = 100): mixed
{
    $currentDelay = $delayMs;
    $lastException = null;

    for ($i = 0; $i < $maxAttempts - 1; $i++) {
        try {
            return $action();
        } catch (\Throwable $e) {
            $lastException = $e;
            usleep($currentDelay * 1000);
            $currentDelay *= 2;
        }
    }

    return $action();
}

// ===== Main =====

$repository = new InMemoryUserRepository();
$eventBus = new EventBus();
$service = new UserService($repository, $eventBus);

// Subscribe to events
$eventBus->subscribe(UserEventType::Created, fn(UserEvent $e) =>
    print("User created: {$e->payload}\n"));
$eventBus->subscribe(UserEventType::Updated, fn(UserEvent $e) =>
    print("User updated: {$e->payload}\n"));
$eventBus->subscribe(UserEventType::Deleted, fn(UserEvent $e) =>
    print("User deleted: {$e->payload}\n"));

// Create users
$service->createUser(new User(1, 'Alice', 'alice@example.com', Role::Admin));
$service->createUser(new User(2, 'Bob', 'bob@example.com', Role::User));
$service->createUser(new User(3, 'Charlie', 'charlie@example.com', Role::Guest));

// Query users
$users = $service->findAll();
print("All users: " . count($users) . "\n");

$admins = array_filter_by_role($users, Role::Admin);
$adminNames = array_map(fn(User $u) => $u->name, $admins);
print("Admins: [" . implode(', ', $adminNames) . "]\n");

// JSON output
print("\nJSON output:\n");
print(json_encode($users, JSON_PRETTY_PRINT) . "\n");


// ===== PHP 8.3+ Typed Class Constants =====

interface HttpStatusInterface
{
    public const int OK = 200;
    public const int CREATED = 201;
    public const int NO_CONTENT = 204;
    public const int BAD_REQUEST = 400;
    public const int UNAUTHORIZED = 401;
    public const int FORBIDDEN = 403;
    public const int NOT_FOUND = 404;
    public const int INTERNAL_ERROR = 500;
}

readonly class HttpConfig implements HttpStatusInterface
{
    public const string DEFAULT_CONTENT_TYPE = 'application/json';
    public const int DEFAULT_TIMEOUT = 30;
    public const array ALLOWED_METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
    public const bool DEBUG_MODE = false;

    public function __construct(
        public string $baseUrl,
        public int $timeout = self::DEFAULT_TIMEOUT,
        public array $defaultHeaders = [],
        public bool $verifySsl = true
    ) {}
}

// ===== #[Override] Attribute (PHP 8.3+) =====

abstract class BaseEntity implements JsonSerializable, Stringable
{
    abstract public function getId(): int|string;
    abstract public function getType(): string;

    public function jsonSerialize(): array
    {
        return ['id' => $this->getId(), 'type' => $this->getType()];
    }

    public function __toString(): string
    {
        return "{$this->getType()}#{$this->getId()}";
    }
}

readonly class Product extends BaseEntity
{
    public function __construct(
        public int $id,
        public string $name,
        public float $price,
        public int $quantity = 0,
        public ?string $sku = null,
        public array $categories = [],
        public bool $isActive = true
    ) {}

    #[\Override]
    public function getId(): int|string
    {
        return $this->id;
    }

    #[\Override]
    public function getType(): string
    {
        return 'Product';
    }

    #[\Override]
    public function jsonSerialize(): array
    {
        return [
            ...parent::jsonSerialize(),
            'name' => $this->name,
            'price' => $this->price,
            'quantity' => $this->quantity,
            'sku' => $this->sku,
            'categories' => $this->categories,
            'isActive' => $this->isActive,
        ];
    }

    public function isInStock(): bool
    {
        return $this->quantity > 0 && $this->isActive;
    }

    public function withPrice(float $price): self
    {
        return new self(
            $this->id,
            $this->name,
            $price,
            $this->quantity,
            $this->sku,
            $this->categories,
            $this->isActive
        );
    }
}

// ===== Advanced Enums =====

enum HttpMethod: string
{
    case GET = 'GET';
    case POST = 'POST';
    case PUT = 'PUT';
    case PATCH = 'PATCH';
    case DELETE = 'DELETE';
    case HEAD = 'HEAD';
    case OPTIONS = 'OPTIONS';

    public function isIdempotent(): bool
    {
        return match($this) {
            self::GET, self::HEAD, self::OPTIONS, self::PUT, self::DELETE => true,
            self::POST, self::PATCH => false,
        };
    }

    public function hasBody(): bool
    {
        return match($this) {
            self::POST, self::PUT, self::PATCH => true,
            default => false,
        };
    }

    public function isSafe(): bool
    {
        return match($this) {
            self::GET, self::HEAD, self::OPTIONS => true,
            default => false,
        };
    }

    public static function fromString(string $method): self
    {
        return self::from(strtoupper($method));
    }
}

enum LogLevel: int
{
    case DEBUG = 0;
    case INFO = 1;
    case NOTICE = 2;
    case WARNING = 3;
    case ERROR = 4;
    case CRITICAL = 5;
    case ALERT = 6;
    case EMERGENCY = 7;

    public function label(): string
    {
        return match($this) {
            self::DEBUG => 'DEBUG',
            self::INFO => 'INFO',
            self::NOTICE => 'NOTICE',
            self::WARNING => 'WARNING',
            self::ERROR => 'ERROR',
            self::CRITICAL => 'CRITICAL',
            self::ALERT => 'ALERT',
            self::EMERGENCY => 'EMERGENCY',
        };
    }

    public function color(): string
    {
        return match($this) {
            self::DEBUG => "\033[37m",      // White
            self::INFO => "\033[34m",       // Blue
            self::NOTICE => "\033[36m",     // Cyan
            self::WARNING => "\033[33m",    // Yellow
            self::ERROR => "\033[31m",      // Red
            self::CRITICAL => "\033[35m",   // Magenta
            self::ALERT => "\033[91m",      // Light Red
            self::EMERGENCY => "\033[41m",  // Red Background
        };
    }

    public function isHigherOrEqual(self $level): bool
    {
        return $this->value >= $level->value;
    }
}

enum ValidationRule: string
{
    case Required = 'required';
    case Email = 'email';
    case Url = 'url';
    case Numeric = 'numeric';
    case Alpha = 'alpha';
    case AlphaNumeric = 'alphanumeric';
    case MinLength = 'min_length';
    case MaxLength = 'max_length';
    case Regex = 'regex';
    case In = 'in';
    case NotIn = 'not_in';
    case Unique = 'unique';
    case Confirmed = 'confirmed';
    case Date = 'date';
    case DateFormat = 'date_format';
    case Before = 'before';
    case After = 'after';
    case Between = 'between';
    case Boolean = 'boolean';
    case Integer = 'integer';
    case Array_ = 'array';
    case Json = 'json';
    case Uuid = 'uuid';
    case Ip = 'ip';

    public function errorMessage(string $field, mixed $param = null): string
    {
        return match($this) {
            self::Required => "The {$field} field is required.",
            self::Email => "The {$field} must be a valid email address.",
            self::Url => "The {$field} must be a valid URL.",
            self::Numeric => "The {$field} must be numeric.",
            self::Alpha => "The {$field} may only contain letters.",
            self::AlphaNumeric => "The {$field} may only contain letters and numbers.",
            self::MinLength => "The {$field} must be at least {$param} characters.",
            self::MaxLength => "The {$field} may not be greater than {$param} characters.",
            self::Regex => "The {$field} format is invalid.",
            self::In => "The selected {$field} is invalid.",
            self::NotIn => "The selected {$field} is invalid.",
            self::Unique => "The {$field} has already been taken.",
            self::Confirmed => "The {$field} confirmation does not match.",
            self::Date => "The {$field} is not a valid date.",
            self::DateFormat => "The {$field} does not match the format {$param}.",
            self::Before => "The {$field} must be a date before {$param}.",
            self::After => "The {$field} must be a date after {$param}.",
            self::Between => "The {$field} must be between the specified values.",
            self::Boolean => "The {$field} field must be true or false.",
            self::Integer => "The {$field} must be an integer.",
            self::Array_ => "The {$field} must be an array.",
            self::Json => "The {$field} must be a valid JSON string.",
            self::Uuid => "The {$field} must be a valid UUID.",
            self::Ip => "The {$field} must be a valid IP address.",
        };
    }
}

// ===== Traits with Abstract Methods =====

trait Timestamps
{
    protected ?DateTimeImmutable $createdAt = null;
    protected ?DateTimeImmutable $updatedAt = null;
    protected ?DateTimeImmutable $deletedAt = null;

    abstract public function touch(): void;

    public function getCreatedAt(): ?DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function getUpdatedAt(): ?DateTimeImmutable
    {
        return $this->updatedAt;
    }

    public function getDeletedAt(): ?DateTimeImmutable
    {
        return $this->deletedAt;
    }

    public function isTrashed(): bool
    {
        return $this->deletedAt !== null;
    }

    protected function setCreatedAt(): void
    {
        $this->createdAt = new DateTimeImmutable();
    }

    protected function setUpdatedAt(): void
    {
        $this->updatedAt = new DateTimeImmutable();
    }

    public function softDelete(): void
    {
        $this->deletedAt = new DateTimeImmutable();
    }

    public function restore(): void
    {
        $this->deletedAt = null;
    }
}

trait HasUuid
{
    protected string $uuid;

    public function getUuid(): string
    {
        return $this->uuid;
    }

    protected function generateUuid(): string
    {
        $data = random_bytes(16);
        $data[6] = chr(ord($data[6]) & 0x0f | 0x40);
        $data[8] = chr(ord($data[8]) & 0x3f | 0x80);

        return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
    }
}

trait Cacheable
{
    protected static array $cache = [];
    protected static int $cacheHits = 0;
    protected static int $cacheMisses = 0;

    abstract protected function getCacheKey(): string;
    abstract protected function getCacheTtl(): int;

    public static function fromCache(string $key): mixed
    {
        if (isset(self::$cache[$key]) && self::$cache[$key]['expires'] > time()) {
            self::$cacheHits++;
            return self::$cache[$key]['value'];
        }
        self::$cacheMisses++;
        return null;
    }

    public function toCache(): void
    {
        self::$cache[$this->getCacheKey()] = [
            'value' => $this,
            'expires' => time() + $this->getCacheTtl(),
        ];
    }

    public static function clearCache(): void
    {
        self::$cache = [];
    }

    public static function getCacheStats(): array
    {
        return [
            'hits' => self::$cacheHits,
            'misses' => self::$cacheMisses,
            'ratio' => self::$cacheHits + self::$cacheMisses > 0
                ? self::$cacheHits / (self::$cacheHits + self::$cacheMisses)
                : 0.0,
        ];
    }
}

trait Serializable
{
    public function toArray(): array
    {
        return get_object_vars($this);
    }

    public function toJson(int $options = 0): string
    {
        return json_encode($this->toArray(), $options | JSON_THROW_ON_ERROR);
    }

    public static function fromArray(array $data): static
    {
        return new static(...$data);
    }

    public static function fromJson(string $json): static
    {
        $data = json_decode($json, true, 512, JSON_THROW_ON_ERROR);
        return static::fromArray($data);
    }
}

// ===== Interfaces =====

interface Renderable
{
    public function render(): string;
}

interface Arrayable
{
    public function toArray(): array;
}

interface Responsable
{
    public function toResponse(): array;
}

/**
 * @template T
 */
interface Pipeline
{
    /**
     * @param T $passable
     * @return T
     */
    public function process(mixed $passable): mixed;
}

interface Middleware
{
    public function handle(Request $request, callable $next): Response;
}

interface EventListener
{
    public function handle(object $event): void;
    public function shouldQueue(): bool;
}

interface QueueableJob
{
    public function handle(): void;
    public function failed(\Throwable $exception): void;
    public function getQueue(): string;
    public function getDelay(): int;
    public function getMaxAttempts(): int;
}

// ===== Abstract Classes =====

abstract class AbstractController
{
    protected array $middleware = [];

    public function __construct(
        protected readonly Request $request,
        protected readonly ResponseFactory $responseFactory
    ) {}

    abstract public function index(): Response;
    abstract public function show(int|string $id): Response;
    abstract public function store(): Response;
    abstract public function update(int|string $id): Response;
    abstract public function destroy(int|string $id): Response;

    protected function json(mixed $data, int $status = 200): Response
    {
        return $this->responseFactory->json($data, $status);
    }

    protected function success(mixed $data = null, string $message = 'Success'): Response
    {
        return $this->json([
            'success' => true,
            'message' => $message,
            'data' => $data,
        ]);
    }

    protected function error(string $message, int $status = 400, array $errors = []): Response
    {
        return $this->json([
            'success' => false,
            'message' => $message,
            'errors' => $errors,
        ], $status);
    }

    protected function notFound(string $message = 'Resource not found'): Response
    {
        return $this->error($message, 404);
    }

    protected function unauthorized(string $message = 'Unauthorized'): Response
    {
        return $this->error($message, 401);
    }

    protected function forbidden(string $message = 'Forbidden'): Response
    {
        return $this->error($message, 403);
    }

    protected function validate(array $rules): Result
    {
        $validator = new Validator($this->request->all(), $rules);
        return $validator->validate();
    }
}

abstract class Model implements JsonSerializable, Arrayable
{
    use Timestamps, HasUuid;

    protected static string $table = '';
    protected static string $primaryKey = 'id';
    protected static array $fillable = [];
    protected static array $hidden = [];
    protected static array $casts = [];

    protected array $attributes = [];
    protected array $original = [];
    protected bool $exists = false;

    public function __construct(array $attributes = [])
    {
        $this->uuid = $this->generateUuid();
        $this->fill($attributes);
        $this->setCreatedAt();
    }

    public function fill(array $attributes): static
    {
        foreach ($attributes as $key => $value) {
            if (in_array($key, static::$fillable)) {
                $this->setAttribute($key, $value);
            }
        }
        return $this;
    }

    public function setAttribute(string $key, mixed $value): void
    {
        if (isset(static::$casts[$key])) {
            $value = $this->castAttribute($key, $value);
        }
        $this->attributes[$key] = $value;
    }

    public function getAttribute(string $key): mixed
    {
        return $this->attributes[$key] ?? null;
    }

    protected function castAttribute(string $key, mixed $value): mixed
    {
        $type = static::$casts[$key];

        return match($type) {
            'int', 'integer' => (int) $value,
            'float', 'double' => (float) $value,
            'string' => (string) $value,
            'bool', 'boolean' => (bool) $value,
            'array' => (array) $value,
            'object' => (object) $value,
            'json' => json_decode($value, true),
            'datetime' => new DateTimeImmutable($value),
            default => $value,
        };
    }

    public function isDirty(?string $attribute = null): bool
    {
        if ($attribute !== null) {
            return ($this->original[$attribute] ?? null) !== ($this->attributes[$attribute] ?? null);
        }
        return $this->original !== $this->attributes;
    }

    public function touch(): void
    {
        $this->setUpdatedAt();
    }

    public function toArray(): array
    {
        return array_diff_key($this->attributes, array_flip(static::$hidden));
    }

    public function jsonSerialize(): array
    {
        return $this->toArray();
    }

    public function __get(string $name): mixed
    {
        return $this->getAttribute($name);
    }

    public function __set(string $name, mixed $value): void
    {
        $this->setAttribute($name, $value);
    }
}

// ===== Union and Intersection Types =====

interface Loggable
{
    public function log(string $message): void;
}

interface Configurable
{
    public function configure(array $config): void;
}

class Logger implements Loggable, Configurable
{
    private LogLevel $minLevel = LogLevel::DEBUG;
    private string $dateFormat = 'Y-m-d H:i:s';
    private ?string $logFile = null;

    public function configure(array $config): void
    {
        $this->minLevel = $config['min_level'] ?? LogLevel::DEBUG;
        $this->dateFormat = $config['date_format'] ?? 'Y-m-d H:i:s';
        $this->logFile = $config['log_file'] ?? null;
    }

    public function log(string $message): void
    {
        $this->write(LogLevel::INFO, $message);
    }

    public function debug(string $message, array $context = []): void
    {
        $this->write(LogLevel::DEBUG, $message, $context);
    }

    public function info(string $message, array $context = []): void
    {
        $this->write(LogLevel::INFO, $message, $context);
    }

    public function warning(string $message, array $context = []): void
    {
        $this->write(LogLevel::WARNING, $message, $context);
    }

    public function error(string $message, array $context = []): void
    {
        $this->write(LogLevel::ERROR, $message, $context);
    }

    public function critical(string $message, array $context = []): void
    {
        $this->write(LogLevel::CRITICAL, $message, $context);
    }

    private function write(LogLevel $level, string $message, array $context = []): void
    {
        if (!$level->isHigherOrEqual($this->minLevel)) {
            return;
        }

        $timestamp = (new DateTimeImmutable())->format($this->dateFormat);
        $contextStr = empty($context) ? '' : ' ' . json_encode($context);
        $formatted = "[{$timestamp}] {$level->label()}: {$message}{$contextStr}\n";

        if ($this->logFile !== null) {
            file_put_contents($this->logFile, $formatted, FILE_APPEND);
        } else {
            echo $level->color() . $formatted . "\033[0m";
        }
    }
}

// Function accepting union types
function processInput(string|int|float|array $input): string
{
    return match(true) {
        is_string($input) => "String: {$input}",
        is_int($input) => "Integer: {$input}",
        is_float($input) => "Float: {$input}",
        is_array($input) => "Array: " . json_encode($input),
    };
}

// Function with intersection type (PHP 8.1+)
function processLoggableConfigurable(Loggable&Configurable $service): void
{
    $service->configure(['min_level' => LogLevel::INFO]);
    $service->log('Service configured successfully');
}

// ===== Anonymous Classes =====

function createCacheAdapter(string $driver): object
{
    return match($driver) {
        'array' => new class implements Arrayable {
