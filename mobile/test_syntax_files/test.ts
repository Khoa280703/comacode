// TypeScript sample file - Advanced patterns and modern TypeScript 5.x
import { EventEmitter } from 'events';
import { createHash, randomUUID } from 'crypto';

// ===== Generic types with constraints =====

interface Entity {
  id: string;
  createdAt: Date;
  updatedAt?: Date;
}

interface Repository<T extends Entity> {
  findById(id: string): Promise<T | null>;
  findAll(options?: QueryOptions): Promise<PaginatedResult<T>>;
  findMany(filter: Partial<T>): Promise<T[]>;
  create(data: Omit<T, 'id' | 'createdAt' | 'updatedAt'>): Promise<T>;
  update(id: string, data: Partial<Omit<T, 'id' | 'createdAt'>>): Promise<T>;
  delete(id: string): Promise<boolean>;
  count(filter?: Partial<T>): Promise<number>;
  exists(id: string): Promise<boolean>;
}

interface QueryOptions {
  page?: number;
  limit?: number;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
  include?: string[];
}

interface PaginatedResult<T> {
  data: T[];
  meta: {
    page: number;
    limit: number;
    total: number;
    totalPages: number;
    hasNext: boolean;
    hasPrev: boolean;
  };
}

// ===== Result Type - Discriminated Union =====

type Result<T, E = Error> =
  | { success: true; data: T; error?: never }
  | { success: false; error: E; data?: never };

namespace Result {
  export function ok<T>(data: T): Result<T, never> {
    return { success: true, data };
  }

  export function err<E>(error: E): Result<never, E> {
    return { success: false, error };
  }

  export function fromPromise<T>(promise: Promise<T>): Promise<Result<T, Error>> {
    return promise
      .then((data) => ok(data))
      .catch((error) => err(error instanceof Error ? error : new Error(String(error))));
  }

  export function map<T, U, E>(result: Result<T, E>, fn: (data: T) => U): Result<U, E> {
    if (result.success) {
      return ok(fn(result.data));
    }
    return result;
  }

  export function flatMap<T, U, E>(result: Result<T, E>, fn: (data: T) => Result<U, E>): Result<U, E> {
    if (result.success) {
      return fn(result.data);
    }
    return result;
  }

  export function unwrap<T, E>(result: Result<T, E>): T {
    if (result.success) {
      return result.data;
    }
    throw result.error;
  }

  export function unwrapOr<T, E>(result: Result<T, E>, defaultValue: T): T {
    if (result.success) {
      return result.data;
    }
    return defaultValue;
  }
}

// ===== Option Type =====

type Option<T> = { some: true; value: T } | { some: false };

namespace Option {
  export function some<T>(value: T): Option<T> {
    return { some: true, value };
  }

  export function none<T = never>(): Option<T> {
    return { some: false };
  }

  export function fromNullable<T>(value: T | null | undefined): Option<T> {
    return value != null ? some(value) : none();
  }

  export function map<T, U>(option: Option<T>, fn: (value: T) => U): Option<U> {
    if (option.some) {
      return some(fn(option.value));
    }
    return none();
  }

  export function flatMap<T, U>(option: Option<T>, fn: (value: T) => Option<U>): Option<U> {
    if (option.some) {
      return fn(option.value);
    }
    return none();
  }

  export function unwrap<T>(option: Option<T>): T {
    if (option.some) {
      return option.value;
    }
    throw new Error('Attempted to unwrap None');
  }

  export function unwrapOr<T>(option: Option<T>, defaultValue: T): T {
    if (option.some) {
      return option.value;
    }
    return defaultValue;
  }

  export function isSome<T>(option: Option<T>): option is { some: true; value: T } {
    return option.some;
  }

  export function isNone<T>(option: Option<T>): option is { some: false } {
    return !option.some;
  }
}

// ===== Utility Types =====

type DeepReadonly<T> = {
  readonly [P in keyof T]: T[P] extends object
    ? T[P] extends Function
      ? T[P]
      : DeepReadonly<T[P]>
    : T[P];
};

type DeepPartial<T> = {
  [P in keyof T]?: T[P] extends object
    ? T[P] extends Array<infer U>
      ? Array<DeepPartial<U>>
      : DeepPartial<T[P]>
    : T[P];
};

type DeepRequired<T> = {
  [P in keyof T]-?: T[P] extends object
    ? T[P] extends Array<infer U>
      ? Array<DeepRequired<U>>
      : DeepRequired<T[P]>
    : T[P];
};

type Mutable<T> = {
  -readonly [P in keyof T]: T[P];
};

type RequiredFields<T, K extends keyof T> = T & Required<Pick<T, K>>;

type OptionalFields<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>;

type PickByType<T, U> = {
  [P in keyof T as T[P] extends U ? P : never]: T[P];
};

type OmitByType<T, U> = {
  [P in keyof T as T[P] extends U ? never : P]: T[P];
};

type Prettify<T> = {
  [K in keyof T]: T[K];
} & {};

// ===== Template Literal Types =====

type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD' | 'OPTIONS';
type ApiVersion = 'v1' | 'v2' | 'v3';
type ApiEndpoint = `/api/${ApiVersion}/${string}`;
type RouteHandler = `${Lowercase<HttpMethod>}:${ApiEndpoint}`;

type EventName<T extends string> = `on${Capitalize<T>}`;
type CSSVariable = `--${string}`;
type HexColor = `#${string}`;
type RGBColor = `rgb(${number}, ${number}, ${number})`;
type RGBAColor = `rgba(${number}, ${number}, ${number}, ${number})`;
type Color = HexColor | RGBColor | RGBAColor;

type Split<S extends string, D extends string> =
  S extends `${infer T}${D}${infer U}` ? [T, ...Split<U, D>] : [S];

type Join<T extends string[], D extends string> =
  T extends [] ? '' :
  T extends [infer F extends string] ? F :
  T extends [infer F extends string, ...infer R extends string[]] ? `${F}${D}${Join<R, D>}` :
  never;

type CamelToSnake<S extends string> =
  S extends `${infer T}${infer U}`
    ? `${T extends Capitalize<T> ? '_' : ''}${Lowercase<T>}${CamelToSnake<U>}`
    : S;

type SnakeToCamel<S extends string> =
  S extends `${infer T}_${infer U}`
    ? `${T}${Capitalize<SnakeToCamel<U>>}`
    : S;

// ===== Conditional Types =====

type ExtractPromise<T> = T extends Promise<infer U> ? U : T;
type ArrayElement<T> = T extends (infer E)[] ? E : never;
type UnwrapArray<T> = T extends Array<infer U> ? U : T;
type Awaitable<T> = T | Promise<T>;
type Nullable<T> = T | null;
type Maybe<T> = T | null | undefined;

type IsArray<T> = T extends any[] ? true : false;
type IsFunction<T> = T extends (...args: any[]) => any ? true : false;
type IsPromise<T> = T extends Promise<any> ? true : false;
type IsNever<T> = [T] extends [never] ? true : false;

type FunctionParams<T> = T extends (...args: infer P) => any ? P : never;
type FunctionReturn<T> = T extends (...args: any[]) => infer R ? R : never;
type ConstructorParams<T> = T extends new (...args: infer P) => any ? P : never;

// ===== Enum with computed values =====

enum HttpStatus {
  // 2xx Success
  OK = 200,
  Created = 201,
  Accepted = 202,
  NoContent = 204,

  // 3xx Redirection
  MovedPermanently = 301,
  Found = 302,
  NotModified = 304,
  TemporaryRedirect = 307,
  PermanentRedirect = 308,

  // 4xx Client Errors
  BadRequest = 400,
  Unauthorized = 401,
  PaymentRequired = 402,
  Forbidden = 403,
  NotFound = 404,
  MethodNotAllowed = 405,
  NotAcceptable = 406,
  RequestTimeout = 408,
  Conflict = 409,
  Gone = 410,
  UnprocessableEntity = 422,
  TooManyRequests = 429,

  // 5xx Server Errors
  InternalServerError = 500,
  NotImplemented = 501,
  BadGateway = 502,
  ServiceUnavailable = 503,
  GatewayTimeout = 504,
}

const enum LogLevel {
  Trace = 0,
  Debug = 1,
  Info = 2,
  Warn = 3,
  Error = 4,
  Fatal = 5,
}

// ===== User Entity =====

interface UserMetadata {
  department?: string;
  team?: string;
  location?: string;
  timezone?: string;
  avatar?: string;
  preferences: {
    theme: 'light' | 'dark' | 'system';
    language: string;
    notifications: {
      email: boolean;
      push: boolean;
      inApp: boolean;
    };
  };
}

interface User extends Entity {
  name: string;
  email: string;
  passwordHash: string;
  role: UserRole;
  isActive: boolean;
  emailVerified: boolean;
  lastLoginAt?: Date;
  metadata: UserMetadata;
}

type UserRole = 'admin' | 'moderator' | 'user' | 'guest';

const UserRolePermissions: Record<UserRole, readonly string[]> = {
  admin: ['read', 'write', 'delete', 'admin', 'manage-users', 'view-analytics'] as const,
  moderator: ['read', 'write', 'delete', 'moderate'] as const,
  user: ['read', 'write'] as const,
  guest: ['read'] as const,
};

// ===== Validation =====

interface ValidationError {
  field: string;
  message: string;
  code: string;
}

interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
}

type Validator<T> = (value: T) => ValidationResult;

namespace Validators {
  export function required(field: string): Validator<unknown> {
    return (value) => {
      if (value === null || value === undefined || value === '') {
        return { valid: false, errors: [{ field, message: `${field} is required`, code: 'REQUIRED' }] };
      }
      return { valid: true, errors: [] };
    };
  }

  export function minLength(field: string, min: number): Validator<string> {
    return (value) => {
      if (value.length < min) {
        return {
          valid: false,
          errors: [{ field, message: `${field} must be at least ${min} characters`, code: 'MIN_LENGTH' }],
        };
      }
      return { valid: true, errors: [] };
    };
  }

  export function maxLength(field: string, max: number): Validator<string> {
    return (value) => {
      if (value.length > max) {
        return {
          valid: false,
          errors: [{ field, message: `${field} must be at most ${max} characters`, code: 'MAX_LENGTH' }],
        };
      }
      return { valid: true, errors: [] };
    };
  }

  export function email(field: string): Validator<string> {
    return (value) => {
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(value)) {
        return { valid: false, errors: [{ field, message: 'Invalid email format', code: 'INVALID_EMAIL' }] };
      }
      return { valid: true, errors: [] };
    };
  }

  export function pattern(field: string, regex: RegExp, message: string): Validator<string> {
    return (value) => {
      if (!regex.test(value)) {
        return { valid: false, errors: [{ field, message, code: 'PATTERN_MISMATCH' }] };
      }
      return { valid: true, errors: [] };
    };
  }

  export function range(field: string, min: number, max: number): Validator<number> {
    return (value) => {
      if (value < min || value > max) {
        return {
          valid: false,
          errors: [{ field, message: `${field} must be between ${min} and ${max}`, code: 'OUT_OF_RANGE' }],
        };
      }
      return { valid: true, errors: [] };
    };
  }

  export function compose<T>(...validators: Validator<T>[]): Validator<T> {
    return (value) => {
      const allErrors: ValidationError[] = [];
      for (const validator of validators) {
        const result = validator(value);
        allErrors.push(...result.errors);
      }
      return { valid: allErrors.length === 0, errors: allErrors };
    };
  }
}

// ===== Event System =====

interface EventMap {
  'user:created': { user: User };
  'user:updated': { user: User; changes: Partial<User> };
  'user:deleted': { userId: string };
  'user:login': { user: User; ip: string; userAgent: string };
  'user:logout': { userId: string };
  'error': { error: Error; context?: Record<string, unknown> };
}

type EventHandler<K extends keyof EventMap> = (payload: EventMap[K]) => void | Promise<void>;

class TypedEventEmitter {
  private emitter = new EventEmitter();
  private handlers = new Map<string, Set<Function>>();

  on<K extends keyof EventMap>(event: K, handler: EventHandler<K>): () => void {
    this.emitter.on(event, handler);

    if (!this.handlers.has(event)) {
      this.handlers.set(event, new Set());
    }
    this.handlers.get(event)!.add(handler);

    return () => this.off(event, handler);
  }

  once<K extends keyof EventMap>(event: K, handler: EventHandler<K>): void {
    this.emitter.once(event, handler);
  }

  off<K extends keyof EventMap>(event: K, handler: EventHandler<K>): void {
    this.emitter.off(event, handler);
    this.handlers.get(event)?.delete(handler);
  }

  emit<K extends keyof EventMap>(event: K, payload: EventMap[K]): void {
    this.emitter.emit(event, payload);
  }

  removeAllListeners(event?: keyof EventMap): void {
    if (event) {
      this.emitter.removeAllListeners(event);
      this.handlers.delete(event);
    } else {
      this.emitter.removeAllListeners();
      this.handlers.clear();
    }
  }

  listenerCount(event: keyof EventMap): number {
    return this.handlers.get(event)?.size ?? 0;
  }
}

// ===== Database Connection =====

interface DatabaseConfig {
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
  ssl?: boolean;
  poolSize?: number;
  connectionTimeout?: number;
}

interface QueryResult<T> {
  rows: T[];
  rowCount: number;
  fields: { name: string; type: string }[];
}

interface Transaction {
  query<T>(sql: string, params?: unknown[]): Promise<QueryResult<T>>;
  commit(): Promise<void>;
  rollback(): Promise<void>;
}

interface DatabaseConnection {
  query<T>(sql: string, params?: unknown[]): Promise<QueryResult<T>>;
  execute(sql: string, params?: unknown[]): Promise<{ rowCount: number }>;
  transaction<T>(fn: (tx: Transaction) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

// ===== Logger Interface =====

interface LogContext {
  requestId?: string;
  userId?: string;
  [key: string]: unknown;
}

interface Logger {
  trace(message: string, context?: LogContext): void;
  debug(message: string, context?: LogContext): void;
  info(message: string, context?: LogContext): void;
  warn(message: string, context?: LogContext): void;
  error(message: string, error?: Error, context?: LogContext): void;
  fatal(message: string, error?: Error, context?: LogContext): void;
  child(context: LogContext): Logger;
}

class ConsoleLogger implements Logger {
  constructor(private context: LogContext = {}) {}

  private formatMessage(level: string, message: string, context: LogContext = {}): string {
    const timestamp = new Date().toISOString();
    const mergedContext = { ...this.context, ...context };
    const contextStr = Object.keys(mergedContext).length > 0
      ? ` ${JSON.stringify(mergedContext)}`
      : '';
    return `[${timestamp}] ${level.toUpperCase()}: ${message}${contextStr}`;
  }

  trace(message: string, context?: LogContext): void {
    console.trace(this.formatMessage('trace', message, context));
  }

  debug(message: string, context?: LogContext): void {
    console.debug(this.formatMessage('debug', message, context));
  }

  info(message: string, context?: LogContext): void {
    console.info(this.formatMessage('info', message, context));
  }

  warn(message: string, context?: LogContext): void {
    console.warn(this.formatMessage('warn', message, context));
  }

  error(message: string, error?: Error, context?: LogContext): void {
    console.error(this.formatMessage('error', message, context), error);
  }

  fatal(message: string, error?: Error, context?: LogContext): void {
    console.error(this.formatMessage('fatal', message, context), error);
  }

  child(context: LogContext): Logger {
    return new ConsoleLogger({ ...this.context, ...context });
  }
}

// ===== Custom Errors =====

class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode: number = 500,
    public readonly details?: Record<string, unknown>
  ) {
    super(message);
    this.name = 'AppError';
    Error.captureStackTrace(this, this.constructor);
  }

  toJSON(): Record<string, unknown> {
    return {
      name: this.name,
      message: this.message,
      code: this.code,
      statusCode: this.statusCode,
      details: this.details,
    };
  }
}

class NotFoundError extends AppError {
  constructor(resource: string, id?: string) {
    super(
      id ? `${resource} with id '${id}' not found` : `${resource} not found`,
      'NOT_FOUND',
      404
    );
    this.name = 'NotFoundError';
  }
}

class ValidationError extends AppError {
  constructor(errors: ValidationError[]) {
    super('Validation failed', 'VALIDATION_ERROR', 400, { errors });
    this.name = 'ValidationError';
  }
}

class AuthenticationError extends AppError {
  constructor(message = 'Authentication required') {
    super(message, 'AUTHENTICATION_REQUIRED', 401);
    this.name = 'AuthenticationError';
  }
}

class AuthorizationError extends AppError {
  constructor(message = 'Insufficient permissions') {
    super(message, 'FORBIDDEN', 403);
    this.name = 'AuthorizationError';
  }
}

class ConflictError extends AppError {
  constructor(message: string) {
    super(message, 'CONFLICT', 409);
    this.name = 'ConflictError';
  }
}

// ===== User Service =====

interface CreateUserDTO {
  name: string;
  email: string;
  password: string;
  role?: UserRole;
  metadata?: Partial<UserMetadata>;
}

interface UpdateUserDTO {
  name?: string;
  email?: string;
  password?: string;
  role?: UserRole;
  isActive?: boolean;
  metadata?: Partial<UserMetadata>;
}

class UserService {
  private cache = new Map<string, User>();
  private eventEmitter = new TypedEventEmitter();

  constructor(
    private readonly db: DatabaseConnection,
    private readonly logger: Logger,
    private readonly config: { cacheEnabled: boolean; cacheTTL: number }
  ) {}

  async findById(id: string): Promise<Result<User, NotFoundError>> {
    // Check cache first
    if (this.config.cacheEnabled && this.cache.has(id)) {
      this.logger.debug(`Cache hit for user ${id}`);
      return Result.ok(this.cache.get(id)!);
    }

    try {
      const result = await this.db.query<User>(
        'SELECT * FROM users WHERE id = $1',
        [id]
      );

      if (result.rows.length === 0) {
        return Result.err(new NotFoundError('User', id));
      }

      const user = result.rows[0];

      if (this.config.cacheEnabled) {
        this.cache.set(id, user);
        setTimeout(() => this.cache.delete(id), this.config.cacheTTL);
      }

      return Result.ok(user);
    } catch (error) {
      this.logger.error('Failed to find user', error as Error, { userId: id });
      throw error;
    }
  }

  async findAll(options: QueryOptions = {}): Promise<PaginatedResult<User>> {
    const { page = 1, limit = 10, sortBy = 'createdAt', sortOrder = 'desc' } = options;
    const offset = (page - 1) * limit;

    const [dataResult, countResult] = await Promise.all([
      this.db.query<User>(
        `SELECT * FROM users ORDER BY ${sortBy} ${sortOrder} LIMIT $1 OFFSET $2`,
        [limit, offset]
      ),
      this.db.query<{ count: number }>('SELECT COUNT(*) as count FROM users', []),
    ]);

    const total = countResult.rows[0].count;
    const totalPages = Math.ceil(total / limit);

    return {
      data: dataResult.rows,
      meta: {
        page,
        limit,
        total,
        totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1,
      },
    };
  }

  async findByEmail(email: string): Promise<Option<User>> {
    const result = await this.db.query<User>(
      'SELECT * FROM users WHERE email = $1',
      [email]
    );

    return result.rows.length > 0 ? Option.some(result.rows[0]) : Option.none();
  }

  async create(dto: CreateUserDTO): Promise<Result<User, ValidationError | ConflictError>> {
    // Validate input
    const validation = this.validateCreateDTO(dto);
    if (!validation.valid) {
      return Result.err(new ValidationError(validation.errors));
    }

    // Check for existing email
    const existing = await this.findByEmail(dto.email);
    if (Option.isSome(existing)) {
      return Result.err(new ConflictError(`User with email '${dto.email}' already exists`));
    }

    // Hash password
    const passwordHash = await this.hashPassword(dto.password);

    const user: User = {
      id: randomUUID(),
      name: dto.name,
      email: dto.email,
      passwordHash,
      role: dto.role ?? 'user',
      isActive: true,
      emailVerified: false,
      createdAt: new Date(),
      metadata: {
        preferences: {
          theme: 'system',
          language: 'en',
          notifications: { email: true, push: true, inApp: true },
        },
        ...dto.metadata,
      },
    };

    await this.db.execute(
      `INSERT INTO users (id, name, email, password_hash, role, is_active, email_verified, created_at, metadata)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [user.id, user.name, user.email, user.passwordHash, user.role, user.isActive, user.emailVerified, user.createdAt, JSON.stringify(user.metadata)]
    );

    if (this.config.cacheEnabled) {
      this.cache.set(user.id, user);
    }

    this.eventEmitter.emit('user:created', { user });
    this.logger.info(`User created: ${user.id}`, { userId: user.id, email: user.email });

    return Result.ok(user);
  }

  async update(id: string, dto: UpdateUserDTO): Promise<Result<User, NotFoundError | ValidationError>> {
    const existingResult = await this.findById(id);
    if (!existingResult.success) {
      return existingResult;
    }

    const existing = existingResult.data;
    const changes: Partial<User> = {};

    if (dto.name !== undefined) changes.name = dto.name;
    if (dto.email !== undefined) changes.email = dto.email;
    if (dto.role !== undefined) changes.role = dto.role;
    if (dto.isActive !== undefined) changes.isActive = dto.isActive;
    if (dto.password !== undefined) {
      changes.passwordHash = await this.hashPassword(dto.password);
    }
    if (dto.metadata !== undefined) {
      changes.metadata = { ...existing.metadata, ...dto.metadata };
    }

    const updated: User = {
      ...existing,
      ...changes,
      updatedAt: new Date(),
    };

    await this.db.execute(
      `UPDATE users SET name = $1, email = $2, role = $3, is_active = $4,
       password_hash = $5, metadata = $6, updated_at = $7 WHERE id = $8`,
      [updated.name, updated.email, updated.role, updated.isActive,
       updated.passwordHash, JSON.stringify(updated.metadata), updated.updatedAt, id]
    );

    if (this.config.cacheEnabled) {
      this.cache.set(id, updated);
    }

    this.eventEmitter.emit('user:updated', { user: updated, changes });
    this.logger.info(`User updated: ${id}`, { userId: id, changes: Object.keys(changes) });

    return Result.ok(updated);
  }

  async delete(id: string): Promise<Result<boolean, NotFoundError>> {
    const existingResult = await this.findById(id);
    if (!existingResult.success) {
      return existingResult;
    }

    await this.db.execute('DELETE FROM users WHERE id = $1', [id]);

    this.cache.delete(id);
    this.eventEmitter.emit('user:deleted', { userId: id });
    this.logger.info(`User deleted: ${id}`, { userId: id });

    return Result.ok(true);
  }

  on<K extends keyof EventMap>(event: K, handler: EventHandler<K>): () => void {
    return this.eventEmitter.on(event, handler);
  }

  clearCache(): void {
    this.cache.clear();
    this.logger.debug('User cache cleared');
  }

  private validateCreateDTO(dto: CreateUserDTO): ValidationResult {
    const validator = Validators.compose(
      Validators.required('name'),
      Validators.minLength('name', 2),
      Validators.maxLength('name', 100)
    );

    const emailValidator = Validators.compose(
      Validators.required('email'),
      Validators.email('email')
    );

    const passwordValidator = Validators.compose(
      Validators.required('password'),
      Validators.minLength('password', 8),
      Validators.pattern('password', /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/, 'Password must contain uppercase, lowercase, and number')
    );

    const results = [
      validator(dto.name),
      emailValidator(dto.email),
      passwordValidator(dto.password),
    ];

    const allErrors = results.flatMap(r => r.errors);
    return { valid: allErrors.length === 0, errors: allErrors };
  }

  private async hashPassword(password: string): Promise<string> {
    const salt = randomUUID();
    const hash = createHash('sha256').update(password + salt).digest('hex');
    return `${salt}:${hash}`;
  }
}

// ===== Async Utilities =====

async function* paginatedFetch<T>(
  fetcher: (page: number) => Promise<PaginatedResult<T>>,
  startPage = 1
): AsyncGenerator<T[], void, unknown> {
  let page = startPage;
  let hasMore = true;

  while (hasMore) {
    const response = await fetcher(page);
    yield response.data;
    hasMore = response.meta.hasNext;
    page++;
  }
}

async function retry<T>(
  fn: () => Promise<T>,
  options: { maxAttempts?: number; delay?: number; backoff?: number } = {}
): Promise<T> {
  const { maxAttempts = 3, delay = 1000, backoff = 2 } = options;
  let currentDelay = delay;
  let lastError: Error | undefined;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error as Error;

      if (attempt < maxAttempts) {
        await new Promise(resolve => setTimeout(resolve, currentDelay));
        currentDelay *= backoff;
      }
    }
  }

  throw lastError;
}

async function timeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  const timeoutPromise = new Promise<never>((_, reject) => {
    setTimeout(() => reject(new Error(`Timeout after ${ms}ms`)), ms);
  });

  return Promise.race([promise, timeoutPromise]);
}

function debounce<T extends (...args: any[]) => any>(
  fn: T,
  delay: number
): (...args: Parameters<T>) => void {
  let timeoutId: NodeJS.Timeout | undefined;

  return (...args: Parameters<T>) => {
    if (timeoutId) {
      clearTimeout(timeoutId);
    }

    timeoutId = setTimeout(() => {
      fn(...args);
    }, delay);
  };
}

function throttle<T extends (...args: any[]) => any>(
  fn: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle = false;

  return (...args: Parameters<T>) => {
    if (!inThrottle) {
      fn(...args);
      inThrottle = true;
      setTimeout(() => {
        inThrottle = false;
      }, limit);
    }
  };
}

// ===== Functional Utilities =====

function pipe<A, B>(a: A, ab: (a: A) => B): B;
function pipe<A, B, C>(a: A, ab: (a: A) => B, bc: (b: B) => C): C;
function pipe<A, B, C, D>(a: A, ab: (a: A) => B, bc: (b: B) => C, cd: (c: C) => D): D;
function pipe<A, B, C, D, E>(a: A, ab: (a: A) => B, bc: (b: B) => C, cd: (c: C) => D, de: (d: D) => E): E;
function pipe(initial: any, ...fns: Function[]): any {
  return fns.reduce((acc, fn) => fn(acc), initial);
}

function compose<A, B>(ab: (a: A) => B): (a: A) => B;
function compose<A, B, C>(bc: (b: B) => C, ab: (a: A) => B): (a: A) => C;
function compose<A, B, C, D>(cd: (c: C) => D, bc: (b: B) => C, ab: (a: A) => B): (a: A) => D;
function compose(...fns: Function[]): Function {
  return (initial: any) => fns.reduceRight((acc, fn) => fn(acc), initial);
}

function curry<A, B, C>(fn: (a: A, b: B) => C): (a: A) => (b: B) => C {
  return (a: A) => (b: B) => fn(a, b);
}

function memoize<T extends (...args: any[]) => any>(fn: T): T {
  const cache = new Map<string, ReturnType<T>>();

  return ((...args: Parameters<T>): ReturnType<T> => {
    const key = JSON.stringify(args);

    if (cache.has(key)) {
      return cache.get(key)!;
    }

    const result = fn(...args);
    cache.set(key, result);
    return result;
  }) as T;
}

// ===== Type Guards =====

function isUser(obj: unknown): obj is User {
  return (
    typeof obj === 'object' &&
    obj !== null &&
    'id' in obj &&
    'name' in obj &&
    'email' in obj &&
    'role' in obj &&
    typeof (obj as User).id === 'string' &&
    typeof (obj as User).name === 'string' &&
    typeof (obj as User).email === 'string'
  );
}

function isError(obj: unknown): obj is Error {
  return obj instanceof Error;
}

function isAppError(obj: unknown): obj is AppError {
  return obj instanceof AppError;
}

function isNonNullable<T>(value: T): value is NonNullable<T> {
  return value !== null && value !== undefined;
}

function assertNever(value: never): never {
  throw new Error(`Unexpected value: ${value}`);
}

// ===== Decorators (Stage 3) =====

function logged(target: any, propertyKey: string, descriptor: PropertyDescriptor) {
  const original = descriptor.value;

  descriptor.value = async function (...args: any[]) {
    console.log(`Calling ${propertyKey} with args:`, args);
    const result = await original.apply(this, args);
    console.log(`${propertyKey} returned:`, result);
    return result;
  };

  return descriptor;
}

function cached(ttl: number) {
  return function (target: any, propertyKey: string, descriptor: PropertyDescriptor) {
    const original = descriptor.value;
    const cache = new Map<string, { value: any; expires: number }>();

    descriptor.value = async function (...args: any[]) {
      const key = JSON.stringify(args);
      const cached = cache.get(key);

      if (cached && cached.expires > Date.now()) {
        return cached.value;
      }

      const result = await original.apply(this, args);
      cache.set(key, { value: result, expires: Date.now() + ttl });
      return result;
    };

    return descriptor;
  };
}

function rateLimited(limit: number, window: number) {
  return function (target: any, propertyKey: string, descriptor: PropertyDescriptor) {
    const original = descriptor.value;
    const calls: number[] = [];

    descriptor.value = async function (...args: any[]) {
      const now = Date.now();
      const windowStart = now - window;

      // Remove old calls
      while (calls.length > 0 && calls[0] < windowStart) {
        calls.shift();
      }

      if (calls.length >= limit) {
        throw new Error(`Rate limit exceeded for ${propertyKey}`);
      }

      calls.push(now);
      return original.apply(this, args);
    };

    return descriptor;
  };
}

// ===== Dependency Injection Container =====

type Constructor<T = any> = new (...args: any[]) => T;
type Token<T = any> = string | symbol | Constructor<T>;

interface Provider<T> {
  useClass?: Constructor<T>;
  useValue?: T;
  useFactory?: () => T | Promise<T>;
}

class Container {
  private instances = new Map<Token, any>();
  private providers = new Map<Token, Provider<any>>();

  register<T>(token: Token<T>, provider: Provider<T>): void {
    this.providers.set(token, provider);
  }

  async resolve<T>(token: Token<T>): Promise<T> {
    // Check for existing instance (singleton)
    if (this.instances.has(token)) {
      return this.instances.get(token);
    }

    const provider = this.providers.get(token);
    if (!provider) {
      throw new Error(`No provider found for ${String(token)}`);
    }

    let instance: T;

    if (provider.useValue !== undefined) {
      instance = provider.useValue;
    } else if (provider.useFactory) {
      instance = await provider.useFactory();
    } else if (provider.useClass) {
      instance = new provider.useClass();
    } else {
      throw new Error(`Invalid provider for ${String(token)}`);
    }

    this.instances.set(token, instance);
    return instance;
  }

  clear(): void {
    this.instances.clear();
    this.providers.clear();
  }
}

// ===== Application Bootstrap =====

async function bootstrap(): Promise<void> {
  const container = new Container();
  const logger = new ConsoleLogger({ app: 'comacode' });

  // Register providers
  container.register('Logger', { useValue: logger });
  container.register('Config', {
    useValue: {
      cacheEnabled: true,
      cacheTTL: 5 * 60 * 1000, // 5 minutes
    },
  });

  logger.info('Application bootstrapped successfully');

  // Example usage
  const config = await container.resolve<{ cacheEnabled: boolean; cacheTTL: number }>('Config');
  logger.info('Configuration loaded', { cacheEnabled: config.cacheEnabled });
}

// ===== Exports =====

export {
  // Types
  Entity,
  Repository,
  QueryOptions,
  PaginatedResult,
  Result,
  Option,
  User,
  UserRole,
  UserMetadata,
  CreateUserDTO,
  UpdateUserDTO,
  ValidationError,
  ValidationResult,

  // Classes
  UserService,
  TypedEventEmitter,
  ConsoleLogger,
  AppError,
  NotFoundError,
  AuthenticationError,
  AuthorizationError,
  ConflictError,
  Container,

  // Enums
  HttpStatus,
  LogLevel,

  // Utilities
  Validators,
  paginatedFetch,
  retry,
  timeout,
  debounce,
  throttle,
  pipe,
  compose,
  curry,
  memoize,

  // Type Guards
  isUser,
  isError,
  isAppError,
  isNonNullable,
  assertNever,

  // Decorators
  logged,
  cached,
  rateLimited,

  // Bootstrap
  bootstrap,
};

