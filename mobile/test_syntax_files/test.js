// JavaScript sample file - Modern ES2024+ patterns
const express = require('express');
const { createHash, randomUUID } = require('crypto');
const { EventEmitter } = require('events');

// ===== Constants =====

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';
const RATE_LIMIT_WINDOW = 60 * 1000; // 1 minute
const MAX_REQUESTS = 100;
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

const HttpStatus = {
  OK: 200,
  Created: 201,
  NoContent: 204,
  BadRequest: 400,
  Unauthorized: 401,
  Forbidden: 403,
  NotFound: 404,
  Conflict: 409,
  UnprocessableEntity: 422,
  TooManyRequests: 429,
  InternalServerError: 500,
};

const UserRole = {
  ADMIN: 'admin',
  MODERATOR: 'moderator',
  USER: 'user',
  GUEST: 'guest',
};

const RolePermissions = {
  [UserRole.ADMIN]: ['read', 'write', 'delete', 'admin', 'manage-users'],
  [UserRole.MODERATOR]: ['read', 'write', 'delete', 'moderate'],
  [UserRole.USER]: ['read', 'write'],
  [UserRole.GUEST]: ['read'],
};

// ===== Result Type =====

class Result {
  constructor(success, data, error) {
    this.success = success;
    this.data = data;
    this.error = error;
  }

  static ok(data) {
    return new Result(true, data, null);
  }

  static err(error) {
    return new Result(false, null, error);
  }

  isOk() {
    return this.success;
  }

  isErr() {
    return !this.success;
  }

  map(fn) {
    if (this.success) {
      return Result.ok(fn(this.data));
    }
    return this;
  }

  flatMap(fn) {
    if (this.success) {
      return fn(this.data);
    }
    return this;
  }

  unwrap() {
    if (this.success) {
      return this.data;
    }
    throw this.error;
  }

  unwrapOr(defaultValue) {
    if (this.success) {
      return this.data;
    }
    return defaultValue;
  }

  toJSON() {
    if (this.success) {
      return { success: true, data: this.data };
    }
    return { success: false, error: this.error?.message || this.error };
  }
}

// ===== Option Type =====

class Option {
  constructor(value, isSome) {
    this._value = value;
    this._isSome = isSome;
  }

  static some(value) {
    return new Option(value, true);
  }

  static none() {
    return new Option(null, false);
  }

  static fromNullable(value) {
    return value != null ? Option.some(value) : Option.none();
  }

  isSome() {
    return this._isSome;
  }

  isNone() {
    return !this._isSome;
  }

  map(fn) {
    if (this._isSome) {
      return Option.some(fn(this._value));
    }
    return this;
  }

  flatMap(fn) {
    if (this._isSome) {
      return fn(this._value);
    }
    return this;
  }

  unwrap() {
    if (this._isSome) {
      return this._value;
    }
    throw new Error('Attempted to unwrap None');
  }

  unwrapOr(defaultValue) {
    if (this._isSome) {
      return this._value;
    }
    return defaultValue;
  }
}

// ===== Custom Errors =====

class AppError extends Error {
  constructor(message, code, statusCode = 500, details = null) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.statusCode = statusCode;
    this.details = details;
    Error.captureStackTrace(this, this.constructor);
  }

  toJSON() {
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
  constructor(resource, id) {
    super(
      id ? `${resource} with id '${id}' not found` : `${resource} not found`,
      'NOT_FOUND',
      404
    );
    this.name = 'NotFoundError';
  }
}

class ValidationError extends AppError {
  constructor(errors) {
    super('Validation failed', 'VALIDATION_ERROR', 400, { errors });
    this.name = 'ValidationError';
    this.errors = errors;
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
  constructor(message) {
    super(message, 'CONFLICT', 409);
    this.name = 'ConflictError';
  }
}

// ===== Validation Utilities =====

const Validators = {
  required: (field) => (value) => {
    if (value === null || value === undefined || value === '') {
      return { valid: false, errors: [{ field, message: `${field} is required`, code: 'REQUIRED' }] };
    }
    return { valid: true, errors: [] };
  },

  minLength: (field, min) => (value) => {
    if (typeof value === 'string' && value.length < min) {
      return {
        valid: false,
        errors: [{ field, message: `${field} must be at least ${min} characters`, code: 'MIN_LENGTH' }],
      };
    }
    return { valid: true, errors: [] };
  },

  maxLength: (field, max) => (value) => {
    if (typeof value === 'string' && value.length > max) {
      return {
        valid: false,
        errors: [{ field, message: `${field} must be at most ${max} characters`, code: 'MAX_LENGTH' }],
      };
    }
    return { valid: true, errors: [] };
  },

  email: (field) => (value) => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (typeof value === 'string' && !emailRegex.test(value)) {
      return { valid: false, errors: [{ field, message: 'Invalid email format', code: 'INVALID_EMAIL' }] };
    }
    return { valid: true, errors: [] };
  },

  pattern: (field, regex, message) => (value) => {
    if (typeof value === 'string' && !regex.test(value)) {
      return { valid: false, errors: [{ field, message, code: 'PATTERN_MISMATCH' }] };
    }
    return { valid: true, errors: [] };
  },

  range: (field, min, max) => (value) => {
    if (typeof value === 'number' && (value < min || value > max)) {
      return {
        valid: false,
        errors: [{ field, message: `${field} must be between ${min} and ${max}`, code: 'OUT_OF_RANGE' }],
      };
    }
    return { valid: true, errors: [] };
  },

  compose: (...validators) => (value) => {
    const allErrors = [];
    for (const validator of validators) {
      const result = validator(value);
      allErrors.push(...result.errors);
    }
    return { valid: allErrors.length === 0, errors: allErrors };
  },
};

function validateUser(data) {
  const errors = [];

  if (!data.name || data.name.length < 2) {
    errors.push({ field: 'name', message: 'Name must be at least 2 characters', code: 'MIN_LENGTH' });
  }

  if (!data.email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.email)) {
    errors.push({ field: 'email', message: 'Valid email is required', code: 'INVALID_EMAIL' });
  }

  if (data.role && !Object.values(UserRole).includes(data.role)) {
    errors.push({ field: 'role', message: 'Invalid role', code: 'INVALID_ROLE' });
  }

  return { valid: errors.length === 0, errors };
}

// ===== In-memory stores =====

const users = new Map([
  ['1', { id: '1', name: 'Alice Admin', email: 'alice@example.com', role: UserRole.ADMIN, isActive: true, createdAt: new Date().toISOString() }],
  ['2', { id: '2', name: 'Bob User', email: 'bob@example.com', role: UserRole.USER, isActive: true, createdAt: new Date().toISOString() }],
  ['3', { id: '3', name: 'Charlie Guest', email: 'charlie@example.com', role: UserRole.GUEST, isActive: true, createdAt: new Date().toISOString() }],
]);

const rateLimitStore = new Map();
const tokenStore = new Map();
const sessionStore = new Map();
const cacheStore = new Map();

// ===== Event Bus =====

class EventBus {
  constructor() {
    this.emitter = new EventEmitter();
    this.handlers = new Map();
  }

  on(event, handler) {
    this.emitter.on(event, handler);
    if (!this.handlers.has(event)) {
      this.handlers.set(event, new Set());
    }
    this.handlers.get(event).add(handler);
    return () => this.off(event, handler);
  }

  once(event, handler) {
    this.emitter.once(event, handler);
  }

  off(event, handler) {
    this.emitter.off(event, handler);
    this.handlers.get(event)?.delete(handler);
  }

  emit(event, payload) {
    this.emitter.emit(event, payload);
  }

  removeAllListeners(event) {
    if (event) {
      this.emitter.removeAllListeners(event);
      this.handlers.delete(event);
    } else {
      this.emitter.removeAllListeners();
      this.handlers.clear();
    }
  }
}

const eventBus = new EventBus();

// Subscribe to events
eventBus.on('user:created', (data) => console.log('User created:', data.user.name));
eventBus.on('user:updated', (data) => console.log('User updated:', data.user.name));
eventBus.on('user:deleted', (data) => console.log('User deleted:', data.userId));
eventBus.on('error', (data) => console.error('Error:', data.error.message));

// ===== Cache Utilities =====

class Cache {
  constructor(ttl = CACHE_TTL) {
    this.store = new Map();
    this.ttl = ttl;
  }

  get(key) {
    const item = this.store.get(key);
    if (!item) return Option.none();

    if (Date.now() > item.expires) {
      this.store.delete(key);
      return Option.none();
    }

    return Option.some(item.value);
  }

  set(key, value, ttl = this.ttl) {
    this.store.set(key, {
      value,
      expires: Date.now() + ttl,
    });
  }

  delete(key) {
    return this.store.delete(key);
  }

  clear() {
    this.store.clear();
  }

  has(key) {
    const item = this.store.get(key);
    if (!item) return false;
    if (Date.now() > item.expires) {
      this.store.delete(key);
      return false;
    }
    return true;
  }

  size() {
    return this.store.size;
  }

  // Cleanup expired entries
  cleanup() {
    const now = Date.now();
    for (const [key, item] of this.store) {
      if (now > item.expires) {
        this.store.delete(key);
      }
    }
  }
}

const userCache = new Cache();

// ===== Middleware =====

const requestLogger = (req, res, next) => {
  const start = Date.now();
  const requestId = randomUUID();
  req.requestId = requestId;

  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`[${new Date().toISOString()}] ${requestId.slice(0, 8)} ${req.method} ${req.path} ${res.statusCode} - ${duration}ms`);
  });

  next();
};

const corsMiddleware = (req, res, next) => {
  const allowedOrigins = ['http://localhost:3000', 'https://comacode.dev'];
  const origin = req.headers.origin;

  if (allowedOrigins.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  }

  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Credentials', 'true');

  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  next();
};

const rateLimiter = (windowMs = RATE_LIMIT_WINDOW, maxRequests = MAX_REQUESTS) => (req, res, next) => {
  const ip = req.ip || req.connection.remoteAddress;
  const now = Date.now();

  if (!rateLimitStore.has(ip)) {
    rateLimitStore.set(ip, { count: 1, windowStart: now });
    return next();
  }

  const record = rateLimitStore.get(ip);

  if (now - record.windowStart > windowMs) {
    record.count = 1;
    record.windowStart = now;
    return next();
  }

  if (record.count >= maxRequests) {
    const retryAfter = Math.ceil((record.windowStart + windowMs - now) / 1000);
    res.setHeader('Retry-After', retryAfter);
    return res.status(HttpStatus.TooManyRequests).json({
      error: 'Too Many Requests',
      retryAfter,
    });
  }

  record.count++;
  next();
};

const authenticate = (req, res, next) => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(HttpStatus.Unauthorized).json({
      error: 'Missing or invalid authorization header',
    });
  }

  const token = authHeader.slice(7);

  try {
    const [userId, signature] = token.split('.');
    const secret = process.env.JWT_SECRET || 'secret';
    const expectedSig = createHash('sha256').update(userId + secret).digest('hex').slice(0, 16);

    if (signature !== expectedSig) {
      throw new AuthenticationError('Invalid token signature');
    }

    const user = users.get(userId);
    if (!user) {
      throw new AuthenticationError('User not found');
    }

    if (!user.isActive) {
      throw new AuthenticationError('User account is disabled');
    }

    req.user = user;
    next();
  } catch (err) {
    if (err instanceof AuthenticationError) {
      return res.status(HttpStatus.Unauthorized).json({ error: err.message });
    }
    return res.status(HttpStatus.Unauthorized).json({ error: 'Invalid token' });
  }
};

const requireRole = (...roles) => (req, res, next) => {
  if (!req.user) {
    return res.status(HttpStatus.Unauthorized).json({ error: 'Authentication required' });
  }

  if (!roles.includes(req.user.role)) {
    return res.status(HttpStatus.Forbidden).json({ error: 'Insufficient permissions' });
  }

  next();
};

const requirePermission = (...permissions) => (req, res, next) => {
  if (!req.user) {
    return res.status(HttpStatus.Unauthorized).json({ error: 'Authentication required' });
  }

  const userPermissions = RolePermissions[req.user.role] || [];
  const hasAllPermissions = permissions.every(p => userPermissions.includes(p));

  if (!hasAllPermissions) {
    return res.status(HttpStatus.Forbidden).json({ error: 'Insufficient permissions' });
  }

  next();
};

// ===== Async Handler =====

const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};

// ===== User Service =====

class UserService {
  constructor(cache, eventBus) {
    this.cache = cache;
    this.eventBus = eventBus;
  }

  findById(id) {
    // Check cache first
    const cached = this.cache.get(id);
    if (cached.isSome()) {
      return Result.ok(cached.unwrap());
    }

    const user = users.get(id);
    if (!user) {
      return Result.err(new NotFoundError('User', id));
    }

    this.cache.set(id, user);
    return Result.ok(user);
  }

  findAll(options = {}) {
    const { role, search, page = 1, limit = 10, sortBy = 'createdAt', sortOrder = 'desc' } = options;

    let result = [...users.values()];

    // Filter by role
    if (role) {
      result = result.filter(u => u.role === role);
    }

    // Search by name or email
    if (search) {
      const query = search.toLowerCase();
      result = result.filter(u =>
        u.name.toLowerCase().includes(query) ||
        u.email.toLowerCase().includes(query)
      );
    }

    // Sort
    result.sort((a, b) => {
      const aVal = a[sortBy];
      const bVal = b[sortBy];
      const comparison = aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
      return sortOrder === 'asc' ? comparison : -comparison;
    });

    // Pagination
    const total = result.length;
    const start = (page - 1) * limit;
    const paginated = result.slice(start, start + limit);

    return {
      data: paginated,
      meta: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
        hasNext: page < Math.ceil(total / limit),
        hasPrev: page > 1,
      },
    };
  }

  findByEmail(email) {
    for (const user of users.values()) {
      if (user.email === email) {
        return Option.some(user);
      }
    }
    return Option.none();
  }

  create(data, createdBy = null) {
    // Validate
    const validation = validateUser(data);
    if (!validation.valid) {
      return Result.err(new ValidationError(validation.errors));
    }

    // Check for existing email
    const existing = this.findByEmail(data.email);
    if (existing.isSome()) {
      return Result.err(new ConflictError(`User with email '${data.email}' already exists`));
    }

    const id = randomUUID();
    const user = {
      id,
      name: data.name,
      email: data.email,
      role: data.role || UserRole.USER,
      isActive: true,
      createdAt: new Date().toISOString(),
      createdBy: createdBy?.id || null,
      metadata: data.metadata || {},
    };

    users.set(id, user);
    this.cache.set(id, user);
    this.eventBus.emit('user:created', { user });

    return Result.ok(user);
  }

  update(id, data, updatedBy = null) {
    const existingResult = this.findById(id);
    if (existingResult.isErr()) {
      return existingResult;
    }

    const existing = existingResult.data;

    // If email is changing, check for conflicts
    if (data.email && data.email !== existing.email) {
      const emailExists = this.findByEmail(data.email);
      if (emailExists.isSome()) {
        return Result.err(new ConflictError(`User with email '${data.email}' already exists`));
      }
    }

    const updated = {
      ...existing,
      ...data,
      id, // Prevent ID change
      updatedAt: new Date().toISOString(),
      updatedBy: updatedBy?.id || null,
    };

    users.set(id, updated);
    this.cache.set(id, updated);
    this.eventBus.emit('user:updated', { user: updated, changes: Object.keys(data) });

    return Result.ok(updated);
  }

  delete(id, deletedBy = null) {
    const existingResult = this.findById(id);
    if (existingResult.isErr()) {
      return existingResult;
    }

    // Prevent self-deletion
    if (deletedBy?.id === id) {
      return Result.err(new ValidationError([{ field: 'id', message: 'Cannot delete yourself', code: 'SELF_DELETE' }]));
    }

    users.delete(id);
    this.cache.delete(id);
    this.eventBus.emit('user:deleted', { userId: id });

    return Result.ok(true);
  }

  clearCache() {
    this.cache.clear();
  }
}

const userService = new UserService(userCache, eventBus);

// ===== Async Utilities =====

async function retry(fn, options = {}) {
  const { maxAttempts = 3, delay = 1000, backoff = 2, onRetry = null } = options;
  let currentDelay = delay;
  let lastError;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;

      if (attempt < maxAttempts) {
        if (onRetry) {
          onRetry(error, attempt);
        }
        await new Promise(resolve => setTimeout(resolve, currentDelay));
        currentDelay *= backoff;
      }
    }
  }

  throw lastError;
}

function timeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`Timeout after ${ms}ms`)), ms)
    ),
  ]);
}

function debounce(fn, delay) {
  let timeoutId;
  return (...args) => {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), delay);
  };
}

function throttle(fn, limit) {
  let inThrottle = false;
  return (...args) => {
    if (!inThrottle) {
      fn(...args);
      inThrottle = true;
      setTimeout(() => { inThrottle = false; }, limit);
    }
  };
}

async function parallel(tasks, concurrency = 5) {
  const results = [];
  const executing = [];

  for (const task of tasks) {
    const p = Promise.resolve().then(() => task());
    results.push(p);

    if (concurrency <= tasks.length) {
      const e = p.finally(() => executing.splice(executing.indexOf(e), 1));
      executing.push(e);
      if (executing.length >= concurrency) {
        await Promise.race(executing);
      }
    }
  }

  return Promise.all(results);
}

async function* paginatedFetch(fetcher, startPage = 1) {
  let page = startPage;
  let hasMore = true;

  while (hasMore) {
    const response = await fetcher(page);
    yield response.data;
    hasMore = response.meta.hasNext;
    page++;
  }
}

// ===== Functional Utilities =====

const pipe = (...fns) => (initial) => fns.reduce((acc, fn) => fn(acc), initial);

const compose = (...fns) => (initial) => fns.reduceRight((acc, fn) => fn(acc), initial);

const curry = (fn) => {
  const curried = (...args) => {
    if (args.length >= fn.length) {
      return fn(...args);
    }
    return (...more) => curried(...args, ...more);
  };
  return curried;
};

const memoize = (fn) => {
  const cache = new Map();
  return (...args) => {
    const key = JSON.stringify(args);
    if (cache.has(key)) {
      return cache.get(key);
    }
    const result = fn(...args);
    cache.set(key, result);
    return result;
  };
};

const partial = (fn, ...presetArgs) => (...laterArgs) => fn(...presetArgs, ...laterArgs);

const once = (fn) => {
  let called = false;
  let result;
  return (...args) => {
    if (!called) {
      called = true;
      result = fn(...args);
    }
    return result;
  };
};

// ===== Array Utilities =====

const groupBy = (arr, keyFn) => {
  return arr.reduce((acc, item) => {
    const key = keyFn(item);
    if (!acc[key]) {
      acc[key] = [];
    }
    acc[key].push(item);
    return acc;
  }, {});
};

const chunk = (arr, size) => {
  const chunks = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
};

const unique = (arr) => [...new Set(arr)];

const uniqueBy = (arr, keyFn) => {
  const seen = new Set();
  return arr.filter(item => {
    const key = keyFn(item);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
};

const flatten = (arr, depth = 1) => arr.flat(depth);

const intersection = (arr1, arr2) => arr1.filter(x => arr2.includes(x));

const difference = (arr1, arr2) => arr1.filter(x => !arr2.includes(x));

const zip = (arr1, arr2) => arr1.map((x, i) => [x, arr2[i]]);

// ===== Object Utilities =====

const pick = (obj, keys) => {
  return keys.reduce((acc, key) => {
    if (key in obj) {
      acc[key] = obj[key];
    }
    return acc;
  }, {});
};

const omit = (obj, keys) => {
  const keySet = new Set(keys);
  return Object.fromEntries(
    Object.entries(obj).filter(([key]) => !keySet.has(key))
  );
};

const deepClone = (obj) => JSON.parse(JSON.stringify(obj));

const deepMerge = (target, source) => {
  const result = { ...target };
  for (const key of Object.keys(source)) {
    if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
      result[key] = deepMerge(result[key] || {}, source[key]);
    } else {
      result[key] = source[key];
    }
  }
  return result;
};

const isEqual = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ===== Initialize Express app =====

const app = express();
app.use(express.json());
app.use(requestLogger);
app.use(corsMiddleware);
app.use(rateLimiter());

// ===== Public routes =====

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    version: process.version,
  });
});

app.get('/api/version', (req, res) => {
  res.json({
    version: '2.0.0',
    api: 'v1',
    environment: process.env.NODE_ENV || 'development',
  });
});

// ===== User routes =====

app.get('/api/users', asyncHandler(async (req, res) => {
  const { role, search, page, limit, sortBy, sortOrder } = req.query;

  const result = userService.findAll({
    role,
    search,
    page: parseInt(page) || 1,
    limit: Math.min(parseInt(limit) || 10, 100),
    sortBy: sortBy || 'createdAt',
    sortOrder: sortOrder || 'desc',
  });

  res.json(result);
}));

app.get('/api/users/:id', asyncHandler(async (req, res) => {
  const result = userService.findById(req.params.id);

  if (result.isErr()) {
    return res.status(result.error.statusCode).json({ error: result.error.message });
  }

  res.json({ data: result.data });
}));

app.post('/api/users', authenticate, requireRole(UserRole.ADMIN), asyncHandler(async (req, res) => {
  const result = userService.create(req.body, req.user);

  if (result.isErr()) {
    return res.status(result.error.statusCode).json(result.error.toJSON());
  }

  res.status(HttpStatus.Created).json({ data: result.data });
}));

app.put('/api/users/:id', authenticate, asyncHandler(async (req, res) => {
  const { id } = req.params;

  // Only admin can update other users
  if (req.user.id !== id && req.user.role !== UserRole.ADMIN) {
    return res.status(HttpStatus.Forbidden).json({ error: 'Cannot update other users' });
  }

  const result = userService.update(id, req.body, req.user);

  if (result.isErr()) {
    return res.status(result.error.statusCode).json(result.error.toJSON());
  }

  res.json({ data: result.data });
}));

app.patch('/api/users/:id', authenticate, asyncHandler(async (req, res) => {
  const { id } = req.params;

  // Only admin can update other users
  if (req.user.id !== id && req.user.role !== UserRole.ADMIN) {
    return res.status(HttpStatus.Forbidden).json({ error: 'Cannot update other users' });
  }

  const result = userService.update(id, req.body, req.user);

  if (result.isErr()) {
    return res.status(result.error.statusCode).json(result.error.toJSON());
  }

  res.json({ data: result.data });
}));

app.delete('/api/users/:id', authenticate, requireRole(UserRole.ADMIN), asyncHandler(async (req, res) => {
  const result = userService.delete(req.params.id, req.user);

  if (result.isErr()) {
    return res.status(result.error.statusCode).json(result.error.toJSON());
  }

  res.status(HttpStatus.NoContent).send();
}));

// ===== Admin routes =====

app.get('/api/admin/stats', authenticate, requireRole(UserRole.ADMIN), asyncHandler(async (req, res) => {
  const allUsers = [...users.values()];

  const stats = {
    totalUsers: allUsers.length,
    activeUsers: allUsers.filter(u => u.isActive).length,
    inactiveUsers: allUsers.filter(u => !u.isActive).length,
    byRole: groupBy(allUsers, u => u.role),
    cacheSize: userCache.size(),
  };

  res.json({ data: stats });
}));

app.post('/api/admin/cache/clear', authenticate, requireRole(UserRole.ADMIN), (req, res) => {
  userService.clearCache();
  res.json({ message: 'Cache cleared successfully' });
});

// ===== Error handlers =====

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  eventBus.emit('error', { error: err, requestId: req.requestId });

  if (err instanceof AppError) {
    return res.status(err.statusCode).json(err.toJSON());
  }

  res.status(HttpStatus.InternalServerError).json({
    error: 'Internal Server Error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined,
    requestId: req.requestId,
  });
});

app.use((req, res) => {
  res.status(HttpStatus.NotFound).json({ error: 'Not Found' });
});

// ===== Server startup =====

const server = app.listen(PORT, HOST, () => {
  console.log(`Server running on http://${HOST}:${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`Process ID: ${process.pid}`);
});

// Graceful shutdown
const gracefulShutdown = (signal) => {
  console.log(`\nReceived ${signal}. Shutting down gracefully...`);
  server.close(() => {
    console.log('HTTP server closed');
    process.exit(0);
  });

  // Force close after 10 seconds
  setTimeout(() => {
    console.error('Could not close connections in time, forcing shutdown');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

module.exports = {
  app,
  userService,
  eventBus,
  Result,
  Option,
  Validators,
  HttpStatus,
  UserRole,
  AppError,
  NotFoundError,
  ValidationError,
  retry,
  timeout,
  debounce,
  throttle,
  parallel,
  pipe,
  compose,
  curry,
  memoize,
  groupBy,
  chunk,
  unique,
  pick,
  omit,
  deepClone,
  deepMerge,
};

