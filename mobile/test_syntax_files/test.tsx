// React TSX sample file - Modern patterns
import React, {
  useState,
  useEffect,
  useCallback,
  useMemo,
  useRef,
  createContext,
  useContext,
  Suspense,
  lazy
} from 'react';

// Types and interfaces
interface User {
  id: string;
  name: string;
  email: string;
  avatar?: string;
  role: 'admin' | 'user' | 'guest';
}

interface ThemeContextValue {
  theme: 'light' | 'dark';
  toggleTheme: () => void;
  colors: {
    primary: string;
    secondary: string;
    background: string;
    text: string;
  };
}

// Props with generics
interface DataTableProps<T> {
  data: T[];
  columns: ColumnDefinition<T>[];
  onRowClick?: (row: T) => void;
  loading?: boolean;
  emptyMessage?: string;
}

interface ColumnDefinition<T> {
  key: keyof T;
  header: string;
  render?: (value: T[keyof T], row: T) => React.ReactNode;
  sortable?: boolean;
  width?: string | number;
}

// Context creation
const ThemeContext = createContext<ThemeContextValue | null>(null);

// Custom hooks
function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (!context) {
    throw new Error('useTheme must be used within ThemeProvider');
  }
  return context;
}

function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debouncedValue;
}

function useFetch<T>(url: string): {
  data: T | null;
  loading: boolean;
  error: Error | null;
  refetch: () => void;
} {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const json = await response.json();
      setData(json);
    } catch (e) {
      setError(e instanceof Error ? e : new Error('Unknown error'));
    } finally {
      setLoading(false);
    }
  }, [url]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  return { data, loading, error, refetch: fetchData };
}

// Generic DataTable component
function DataTable<T extends { id: string }>({
  data,
  columns,
  onRowClick,
  loading = false,
  emptyMessage = 'No data available',
}: DataTableProps<T>): JSX.Element {
  const [sortColumn, setSortColumn] = useState<keyof T | null>(null);
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  const sortedData = useMemo(() => {
    if (!sortColumn) return data;

    return [...data].sort((a, b) => {
      const aValue = a[sortColumn];
      const bValue = b[sortColumn];

      if (aValue < bValue) return sortDirection === 'asc' ? -1 : 1;
      if (aValue > bValue) return sortDirection === 'asc' ? 1 : -1;
      return 0;
    });
  }, [data, sortColumn, sortDirection]);

  const handleSort = (column: keyof T) => {
    if (sortColumn === column) {
      setSortDirection(prev => prev === 'asc' ? 'desc' : 'asc');
    } else {
      setSortColumn(column);
      setSortDirection('asc');
    }
  };

  if (loading) {
    return (
      <div className="table-loading">
        <div className="spinner" />
        <span>Loading...</span>
      </div>
    );
  }

  if (data.length === 0) {
    return (
      <div className="table-empty">
        <span>{emptyMessage}</span>
      </div>
    );
  }

  return (
    <table className="data-table">
      <thead>
        <tr>
          {columns.map(col => (
            <th
              key={String(col.key)}
              style={{ width: col.width }}
              onClick={() => col.sortable && handleSort(col.key)}
              className={col.sortable ? 'sortable' : ''}
            >
              {col.header}
              {sortColumn === col.key && (
                <span className="sort-indicator">
                  {sortDirection === 'asc' ? '▲' : '▼'}
                </span>
              )}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {sortedData.map(row => (
          <tr
            key={row.id}
            onClick={() => onRowClick?.(row)}
            className={onRowClick ? 'clickable' : ''}
          >
            {columns.map(col => (
              <td key={String(col.key)}>
                {col.render
                  ? col.render(row[col.key], row)
                  : String(row[col.key])
                }
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// User card component with memo
const UserCard = React.memo<{ user: User; onSelect: (user: User) => void }>(
  ({ user, onSelect }) => {
    const { colors } = useTheme();

    return (
      <div
        className="user-card"
        style={{ backgroundColor: colors.background }}
        onClick={() => onSelect(user)}
      >
        <img
          src={user.avatar || '/default-avatar.png'}
          alt={user.name}
          className="avatar"
        />
        <div className="user-info">
          <h3 style={{ color: colors.text }}>{user.name}</h3>
          <p style={{ color: colors.secondary }}>{user.email}</p>
          <span className={`badge badge-${user.role}`}>
            {user.role}
          </span>
        </div>
      </div>
    );
  }
);

UserCard.displayName = 'UserCard';

// Search input with debounce
const SearchInput: React.FC<{
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}> = ({ value, onChange, placeholder = 'Search...' }) => {
  const [localValue, setLocalValue] = useState(value);
  const debouncedValue = useDebounce(localValue, 300);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    onChange(debouncedValue);
  }, [debouncedValue, onChange]);

  return (
    <div className="search-input">
      <input
        ref={inputRef}
        type="text"
        value={localValue}
        onChange={e => setLocalValue(e.target.value)}
        placeholder={placeholder}
      />
      {localValue && (
        <button
          className="clear-button"
          onClick={() => {
            setLocalValue('');
            inputRef.current?.focus();
          }}
        >
          ✕
        </button>
      )}
    </div>
  );
};

// Lazy loaded component
const UserDetails = lazy(() => import('./UserDetails'));

// Main app component
// ===== Advanced TypeScript Types =====

// Conditional types
type IsArray<T> = T extends Array<infer U> ? U : never;
type Flatten<T> = T extends Array<infer U> ? Flatten<U> : T;

// Template literal types
type EventName = 'click' | 'hover' | 'focus';
type EventHandler = `on${Capitalize<EventName>}`;

// Mapped types with modifiers
type Mutable<T> = { -readonly [P in keyof T]: T[P] };
type Optional<T> = { [P in keyof T]?: T[P] };
type Required<T> = { [P in keyof T]-?: T[P] };

// Utility type combinations
type DeepPartial<T> = {
  [P in keyof T]?: T[P] extends object ? DeepPartial<T[P]> : T[P];
};

type DeepReadonly<T> = {
  readonly [P in keyof T]: T[P] extends object ? DeepReadonly<T[P]> : T[P];
};

// Discriminated unions
type Result<T, E = Error> =
  | { success: true; data: T }
  | { success: false; error: E };

type AsyncState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };

// ===== Custom Hooks =====

function useLocalStorage<T>(
  key: string,
  initialValue: T
): [T, (value: T | ((prev: T) => T)) => void] {
  const [storedValue, setStoredValue] = useState<T>(() => {
    try {
      const item = window.localStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch {
      return initialValue;
    }
  });

  const setValue = useCallback(
    (value: T | ((prev: T) => T)) => {
      setStoredValue(prev => {
        const valueToStore = value instanceof Function ? value(prev) : value;
        window.localStorage.setItem(key, JSON.stringify(valueToStore));
        return valueToStore;
      });
    },
    [key]
  );

  return [storedValue, setValue];
}

function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() =>
    typeof window !== 'undefined' ? window.matchMedia(query).matches : false
  );

  useEffect(() => {
    const mediaQuery = window.matchMedia(query);
    const handler = (e: MediaQueryListEvent) => setMatches(e.matches);

    mediaQuery.addEventListener('change', handler);
    return () => mediaQuery.removeEventListener('change', handler);
  }, [query]);

  return matches;
}

function useClickOutside<T extends HTMLElement>(
  callback: () => void
): React.RefObject<T> {
  const ref = useRef<T>(null);

  useEffect(() => {
    const handleClick = (event: MouseEvent) => {
      if (ref.current && !ref.current.contains(event.target as Node)) {
        callback();
      }
    };

    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [callback]);

  return ref;
}

function useAsync<T>(
  asyncFunction: () => Promise<T>,
  deps: React.DependencyList = []
): AsyncState<T> & { execute: () => Promise<void> } {
  const [state, setState] = useState<AsyncState<T>>({ status: 'idle' });

  const execute = useCallback(async () => {
    setState({ status: 'loading' });
    try {
      const data = await asyncFunction();
      setState({ status: 'success', data });
    } catch (error) {
      setState({ status: 'error', error: error as Error });
    }
  }, deps);

  return { ...state, execute };
}

function useIntersectionObserver(
  options: IntersectionObserverInit = {}
): [React.RefObject<HTMLDivElement>, boolean] {
  const ref = useRef<HTMLDivElement>(null);
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    const observer = new IntersectionObserver(([entry]) => {
      setIsVisible(entry.isIntersecting);
    }, options);

    if (ref.current) {
      observer.observe(ref.current);
    }

    return () => observer.disconnect();
  }, [options.threshold, options.root, options.rootMargin]);

  return [ref, isVisible];
}

// ===== Higher-Order Components =====

function withLoading<P extends object>(
  WrappedComponent: React.ComponentType<P>
): React.FC<P & { loading?: boolean }> {
  return function WithLoadingComponent({ loading, ...props }) {
    if (loading) {
      return (
        <div className="loading-wrapper">
          <div className="spinner" />
        </div>
      );
    }
    return <WrappedComponent {...(props as P)} />;
  };
}

function withErrorBoundary<P extends object>(
  WrappedComponent: React.ComponentType<P>,
  FallbackComponent: React.ComponentType<{ error: Error }>
): React.ComponentType<P> {
  return class ErrorBoundaryWrapper extends React.Component<P, { error: Error | null }> {
    state = { error: null };

    static getDerivedStateFromError(error: Error) {
      return { error };
    }

    render() {
      if (this.state.error) {
        return <FallbackComponent error={this.state.error} />;
      }
      return <WrappedComponent {...this.props} />;
    }
  };
}

// ===== Compound Components Pattern =====

interface TabsContextValue {
  activeTab: string;
  setActiveTab: (id: string) => void;
}

const TabsContext = createContext<TabsContextValue | null>(null);

interface TabsProps {
  defaultTab?: string;
  children: React.ReactNode;
  onChange?: (tabId: string) => void;
}

function Tabs({ defaultTab, children, onChange }: TabsProps): JSX.Element {
  const [activeTab, setActiveTab] = useState(defaultTab || '');

  const handleTabChange = useCallback((id: string) => {
    setActiveTab(id);
    onChange?.(id);
  }, [onChange]);

  return (
    <TabsContext.Provider value={{ activeTab, setActiveTab: handleTabChange }}>
      <div className="tabs-container">{children}</div>
    </TabsContext.Provider>
  );
}

function TabList({ children }: { children: React.ReactNode }): JSX.Element {
  return <div className="tab-list" role="tablist">{children}</div>;
}

function Tab({ id, children }: { id: string; children: React.ReactNode }): JSX.Element {
  const context = useContext(TabsContext);
  if (!context) throw new Error('Tab must be used within Tabs');

  const { activeTab, setActiveTab } = context;

  return (
    <button
      role="tab"
      aria-selected={activeTab === id}
      className={`tab ${activeTab === id ? 'active' : ''}`}
      onClick={() => setActiveTab(id)}
    >
      {children}
    </button>
  );
}

function TabPanel({ id, children }: { id: string; children: React.ReactNode }): JSX.Element | null {
  const context = useContext(TabsContext);
  if (!context) throw new Error('TabPanel must be used within Tabs');

  if (context.activeTab !== id) return null;

  return (
    <div role="tabpanel" className="tab-panel">
      {children}
    </div>
  );
}

Tabs.List = TabList;
Tabs.Tab = Tab;
Tabs.Panel = TabPanel;

// ===== Render Props Pattern =====

interface MousePosition {
  x: number;
  y: number;
}

interface MouseTrackerProps {
  children: (position: MousePosition) => React.ReactNode;
}

function MouseTracker({ children }: MouseTrackerProps): JSX.Element {
  const [position, setPosition] = useState<MousePosition>({ x: 0, y: 0 });

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      setPosition({ x: e.clientX, y: e.clientY });
    };

    window.addEventListener('mousemove', handleMouseMove);
    return () => window.removeEventListener('mousemove', handleMouseMove);
  }, []);

  return <>{children(position)}</>;
}

// ===== Form Handling with Validation =====

interface FormField<T> {
  value: T;
  error: string | null;
  touched: boolean;
}

interface FormState<T extends Record<string, unknown>> {
  fields: { [K in keyof T]: FormField<T[K]> };
  isValid: boolean;
  isSubmitting: boolean;
}

type Validator<T> = (value: T) => string | null;

interface UseFormConfig<T extends Record<string, unknown>> {
  initialValues: T;
  validators?: { [K in keyof T]?: Validator<T[K]> };
  onSubmit: (values: T) => Promise<void>;
}

function useForm<T extends Record<string, unknown>>({
  initialValues,
  validators = {},
  onSubmit,
}: UseFormConfig<T>) {
  const [fields, setFields] = useState<FormState<T>['fields']>(() => {
    const initial = {} as FormState<T>['fields'];
    for (const key in initialValues) {
      initial[key] = {
        value: initialValues[key],
        error: null,
        touched: false,
      };
    }
    return initial;
  });

  const [isSubmitting, setIsSubmitting] = useState(false);

  const setValue = useCallback(<K extends keyof T>(name: K, value: T[K]) => {
    setFields(prev => ({
      ...prev,
      [name]: {
        ...prev[name],
        value,
        error: validators[name]?.(value) || null,
      },
    }));
  }, [validators]);

  const setTouched = useCallback(<K extends keyof T>(name: K) => {
    setFields(prev => ({
      ...prev,
      [name]: { ...prev[name], touched: true },
    }));
  }, []);

  const isValid = useMemo(() => {
    return Object.values(fields).every(field => !field.error);
  }, [fields]);

  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isValid || isSubmitting) return;

    setIsSubmitting(true);
    try {
      const values = Object.fromEntries(
        Object.entries(fields).map(([key, field]) => [key, field.value])
      ) as T;
      await onSubmit(values);
    } finally {
      setIsSubmitting(false);
    }
  }, [fields, isValid, isSubmitting, onSubmit]);

  return { fields, setValue, setTouched, isValid, isSubmitting, handleSubmit };
}

// ===== Portal Component =====

interface PortalProps {
  children: React.ReactNode;
  containerId?: string;
}

function Portal({ children, containerId = 'portal-root' }: PortalProps): React.ReactPortal | null {
  const [container, setContainer] = useState<HTMLElement | null>(null);

  useEffect(() => {
    let el = document.getElementById(containerId);
    if (!el) {
      el = document.createElement('div');
      el.id = containerId;
      document.body.appendChild(el);
    }
    setContainer(el);
  }, [containerId]);

  if (!container) return null;
  return ReactDOM.createPortal(children, container);
}

// ===== Modal Component =====

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title?: string;
  children: React.ReactNode;
  size?: 'sm' | 'md' | 'lg';
}

function Modal({ isOpen, onClose, title, children, size = 'md' }: ModalProps): JSX.Element | null {
  const modalRef = useClickOutside<HTMLDivElement>(onClose);

  useEffect(() => {
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };

    if (isOpen) {
      document.addEventListener('keydown', handleEscape);
      document.body.style.overflow = 'hidden';
    }

    return () => {
      document.removeEventListener('keydown', handleEscape);
      document.body.style.overflow = '';
    };
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <Portal>
      <div className="modal-overlay">
        <div ref={modalRef} className={`modal modal-${size}`} role="dialog" aria-modal="true">
          {title && (
            <div className="modal-header">
              <h2>{title}</h2>
              <button onClick={onClose} aria-label="Close">×</button>
            </div>
          )}
          <div className="modal-body">{children}</div>
        </div>
      </div>
    </Portal>
  );
}

// ===== Virtualized List =====

interface VirtualizedListProps<T> {
  items: T[];
  itemHeight: number;
  containerHeight: number;
  renderItem: (item: T, index: number) => React.ReactNode;
}

function VirtualizedList<T>({
  items,
  itemHeight,
  containerHeight,
  renderItem,
}: VirtualizedListProps<T>): JSX.Element {
  const [scrollTop, setScrollTop] = useState(0);

  const startIndex = Math.floor(scrollTop / itemHeight);
  const endIndex = Math.min(
    startIndex + Math.ceil(containerHeight / itemHeight) + 1,
    items.length
  );

  const visibleItems = items.slice(startIndex, endIndex);
  const offsetY = startIndex * itemHeight;

  return (
    <div
      className="virtualized-list"
      style={{ height: containerHeight, overflow: 'auto' }}
      onScroll={(e) => setScrollTop(e.currentTarget.scrollTop)}
    >
      <div style={{ height: items.length * itemHeight, position: 'relative' }}>
        <div style={{ transform: `translateY(${offsetY}px)` }}>
          {visibleItems.map((item, index) => (
            <div key={startIndex + index} style={{ height: itemHeight }}>
              {renderItem(item, startIndex + index)}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ===== Animation Hook =====

function useSpring(target: number, config = { stiffness: 100, damping: 10 }): number {
  const [value, setValue] = useState(target);
  const velocity = useRef(0);

  useEffect(() => {
    let animationId: number;

    const animate = () => {
      const force = (target - value) * (config.stiffness / 1000);
      velocity.current = velocity.current * (1 - config.damping / 100) + force;
      const newValue = value + velocity.current;

      if (Math.abs(target - newValue) < 0.01 && Math.abs(velocity.current) < 0.01) {
        setValue(target);
        return;
      }

      setValue(newValue);
      animationId = requestAnimationFrame(animate);
    };

    animationId = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(animationId);
  }, [target, value, config.stiffness, config.damping]);

  return value;
}

// ===== Toast Notification System =====

interface Toast {
  id: string;
  message: string;
  type: 'success' | 'error' | 'warning' | 'info';
  duration?: number;
}

interface ToastContextValue {
  toasts: Toast[];
  addToast: (toast: Omit<Toast, 'id'>) => void;
  removeToast: (id: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

function ToastProvider({ children }: { children: React.ReactNode }): JSX.Element {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const addToast = useCallback((toast: Omit<Toast, 'id'>) => {
    const id = Math.random().toString(36).slice(2);
    setToasts(prev => [...prev, { ...toast, id }]);

    if (toast.duration !== 0) {
      setTimeout(() => {
        setToasts(prev => prev.filter(t => t.id !== id));
      }, toast.duration || 5000);
    }
  }, []);

  const removeToast = useCallback((id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id));
  }, []);

  return (
    <ToastContext.Provider value={{ toasts, addToast, removeToast }}>
      {children}
      <Portal>
        <div className="toast-container">
          {toasts.map(toast => (
            <div key={toast.id} className={`toast toast-${toast.type}`}>
              <span>{toast.message}</span>
              <button onClick={() => removeToast(toast.id)}>×</button>
            </div>
          ))}
        </div>
      </Portal>
    </ToastContext.Provider>
  );
}

function useToast(): Omit<ToastContextValue, 'toasts'> {
  const context = useContext(ToastContext);
  if (!context) throw new Error('useToast must be used within ToastProvider');
  return { addToast: context.addToast, removeToast: context.removeToast };
}

// ===== Data Fetching with React Query Pattern =====

interface QueryOptions<T> {
  queryKey: string[];
  queryFn: () => Promise<T>;
  staleTime?: number;
  cacheTime?: number;
  enabled?: boolean;
  onSuccess?: (data: T) => void;
  onError?: (error: Error) => void;
}

interface QueryResult<T> {
  data: T | undefined;
  error: Error | null;
  isLoading: boolean;
  isError: boolean;
  isSuccess: boolean;
  refetch: () => Promise<void>;
}

const queryCache = new Map<string, { data: unknown; timestamp: number }>();

function useQuery<T>({
  queryKey,
  queryFn,
  staleTime = 0,
  enabled = true,
  onSuccess,
  onError,
}: QueryOptions<T>): QueryResult<T> {
  const cacheKey = queryKey.join(':');
  const [data, setData] = useState<T | undefined>(() => {
    const cached = queryCache.get(cacheKey);
    if (cached && Date.now() - cached.timestamp < staleTime) {
      return cached.data as T;
    }
    return undefined;
  });
  const [error, setError] = useState<Error | null>(null);
  const [isLoading, setIsLoading] = useState(!data);

  const fetch = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      const result = await queryFn();
      setData(result);
      queryCache.set(cacheKey, { data: result, timestamp: Date.now() });
      onSuccess?.(result);
    } catch (e) {
      const err = e as Error;
      setError(err);
      onError?.(err);
    } finally {
      setIsLoading(false);
    }
  }, [cacheKey, queryFn, onSuccess, onError]);

  useEffect(() => {
    if (enabled) {
      fetch();
    }
  }, [enabled, fetch]);

  return {
    data,
    error,
    isLoading,
    isError: !!error,
    isSuccess: !!data && !error,
    refetch: fetch,
  };
}

// Import ReactDOM for portal
import ReactDOM from 'react-dom';

// Main app component
export default function UserDashboard(): JSX.Element {
  const [users, setUsers] = useState<User[]>([]);
  const [selectedUser, setSelectedUser] = useState<User | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const { data, loading, error } = useFetch<User[]>('/api/users');

  useEffect(() => {
    if (data) {
      setUsers(data);
    }
  }, [data]);

  const filteredUsers = useMemo(() => {
    if (!searchQuery) return users;
    const query = searchQuery.toLowerCase();
    return users.filter(
      user =>
        user.name.toLowerCase().includes(query) ||
        user.email.toLowerCase().includes(query)
    );
  }, [users, searchQuery]);

  const columns: ColumnDefinition<User>[] = useMemo(() => [
    { key: 'name', header: 'Name', sortable: true },
    { key: 'email', header: 'Email', sortable: true },
    {
      key: 'role',
      header: 'Role',
      render: (value) => (
        <span className={`badge badge-${value}`}>{String(value)}</span>
      ),
    },
  ], []);

  if (error) {
    return (
      <div className="error-state">
        <h2>Error loading users</h2>
        <p>{error.message}</p>
      </div>
    );
  }

  return (
    <div className="dashboard">
      <header>
        <h1>User Dashboard</h1>
        <SearchInput
          value={searchQuery}
          onChange={setSearchQuery}
          placeholder="Search users..."
        />
      </header>

      <main>
        <section className="user-list">
          <DataTable
            data={filteredUsers}
            columns={columns}
            loading={loading}
            onRowClick={setSelectedUser}
            emptyMessage="No users found"
          />
        </section>

        {selectedUser && (
          <aside className="user-details">
            <Suspense fallback={<div>Loading details...</div>}>
              <UserDetails user={selectedUser} />
            </Suspense>
          </aside>
        )}
      </main>
    </div>
  );
}
