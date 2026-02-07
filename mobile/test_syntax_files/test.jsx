// React JSX Comprehensive Sample File - Modern React 18+ Patterns
// This file demonstrates advanced React patterns, hooks, context, and best practices

import React, {
  useState,
  useEffect,
  useCallback,
  useMemo,
  useRef,
  useContext,
  useReducer,
  useLayoutEffect,
  useImperativeHandle,
  forwardRef,
  memo,
  lazy,
  Suspense,
  createContext,
  Fragment,
  startTransition,
  useDeferredValue,
  useTransition,
  useId,
  useSyncExternalStore,
} from 'react';
import PropTypes from 'prop-types';

// ============================================================================
// SECTION 1: STYLED COMPONENTS / CSS-IN-JS PATTERNS
// ============================================================================

/**
 * Simple CSS-in-JS implementation for styling components
 * Provides theme-aware styling with dynamic prop-based styles
 */
const createStyled = (Component) => (styles) => {
  const StyledComponent = forwardRef((props, ref) => {
    const theme = useContext(ThemeContext);
    const computedStyles = typeof styles === 'function'
      ? styles({ ...props, theme })
      : styles;

    return (
      <Component
        ref={ref}
        {...props}
        style={{ ...computedStyles, ...props.style }}
      />
    );
  });

  StyledComponent.displayName = `Styled(${Component.displayName || Component.name || 'Component'})`;
  return StyledComponent;
};

// Theme definition with comprehensive design tokens
const lightTheme = {
  name: 'light',
  colors: {
    primary: '#3b82f6',
    primaryHover: '#2563eb',
    primaryLight: '#dbeafe',
    secondary: '#6b7280',
    secondaryHover: '#4b5563',
    success: '#10b981',
    successHover: '#059669',
    warning: '#f59e0b',
    warningHover: '#d97706',
    danger: '#ef4444',
    dangerHover: '#dc2626',
    info: '#06b6d4',
    infoHover: '#0891b2',
    background: '#ffffff',
    backgroundSecondary: '#f9fafb',
    backgroundTertiary: '#f3f4f6',
    surface: '#ffffff',
    surfaceHover: '#f9fafb',
    text: '#111827',
    textSecondary: '#6b7280',
    textTertiary: '#9ca3af',
    textInverse: '#ffffff',
    border: '#e5e7eb',
    borderFocus: '#3b82f6',
    shadow: 'rgba(0, 0, 0, 0.1)',
    shadowHeavy: 'rgba(0, 0, 0, 0.25)',
    overlay: 'rgba(0, 0, 0, 0.5)',
  },
  spacing: {
    xs: '4px',
    sm: '8px',
    md: '16px',
    lg: '24px',
    xl: '32px',
    xxl: '48px',
  },
  borderRadius: {
    sm: '4px',
    md: '8px',
    lg: '12px',
    xl: '16px',
    full: '9999px',
  },
  typography: {
    fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
    fontSizeXs: '12px',
    fontSizeSm: '14px',
    fontSizeMd: '16px',
    fontSizeLg: '18px',
    fontSizeXl: '24px',
    fontSizeXxl: '32px',
    fontWeightNormal: 400,
    fontWeightMedium: 500,
    fontWeightSemibold: 600,
    fontWeightBold: 700,
    lineHeightTight: 1.25,
    lineHeightNormal: 1.5,
    lineHeightRelaxed: 1.75,
  },
  transitions: {
    fast: '150ms ease',
    normal: '250ms ease',
    slow: '350ms ease',
  },
  breakpoints: {
    sm: '640px',
    md: '768px',
    lg: '1024px',
    xl: '1280px',
  },
  zIndex: {
    dropdown: 1000,
    sticky: 1020,
    fixed: 1030,
    modalBackdrop: 1040,
    modal: 1050,
    popover: 1060,
    tooltip: 1070,
  },
};

const darkTheme = {
  ...lightTheme,
  name: 'dark',
  colors: {
    ...lightTheme.colors,
    primary: '#60a5fa',
    primaryHover: '#3b82f6',
    primaryLight: '#1e3a5f',
    background: '#0f172a',
    backgroundSecondary: '#1e293b',
    backgroundTertiary: '#334155',
    surface: '#1e293b',
    surfaceHover: '#334155',
    text: '#f8fafc',
    textSecondary: '#94a3b8',
    textTertiary: '#64748b',
    border: '#334155',
    shadow: 'rgba(0, 0, 0, 0.3)',
    shadowHeavy: 'rgba(0, 0, 0, 0.5)',
  },
};

// ============================================================================
// SECTION 2: CONTEXT PROVIDERS
// ============================================================================

/**
 * Theme Context - Provides theming capabilities throughout the app
 */
const ThemeContext = createContext(lightTheme);

const ThemeProvider = ({ children, initialTheme = 'light' }) => {
  const [themeName, setThemeName] = useState(initialTheme);
  const theme = themeName === 'dark' ? darkTheme : lightTheme;

  const toggleTheme = useCallback(() => {
    setThemeName((prev) => (prev === 'light' ? 'dark' : 'light'));
  }, []);

  const setTheme = useCallback((name) => {
    if (name === 'light' || name === 'dark') {
      setThemeName(name);
    }
  }, []);

  const value = useMemo(
    () => ({
      theme,
      themeName,
      toggleTheme,
      setTheme,
      isDark: themeName === 'dark',
    }),
    [theme, themeName, toggleTheme, setTheme]
  );

  return (
    <ThemeContext.Provider value={value}>
      <div
        style={{
          backgroundColor: theme.colors.background,
          color: theme.colors.text,
          minHeight: '100vh',
          transition: `background-color ${theme.transitions.normal}, color ${theme.transitions.normal}`,
        }}
      >
        {children}
      </div>
    </ThemeContext.Provider>
  );
};

ThemeProvider.propTypes = {
  children: PropTypes.node.isRequired,
  initialTheme: PropTypes.oneOf(['light', 'dark']),
};

/**
 * Authentication Context - Manages user authentication state
 */
const AuthContext = createContext(null);

const authReducer = (state, action) => {
  switch (action.type) {
    case 'LOGIN_START':
      return { ...state, isLoading: true, error: null };
    case 'LOGIN_SUCCESS':
      return {
        ...state,
        isLoading: false,
        isAuthenticated: true,
        user: action.payload,
        error: null,
      };
    case 'LOGIN_FAILURE':
      return {
        ...state,
        isLoading: false,
        isAuthenticated: false,
        user: null,
        error: action.payload,
      };
    case 'LOGOUT':
      return {
        ...state,
        isLoading: false,
        isAuthenticated: false,
        user: null,
        error: null,
      };
    case 'UPDATE_USER':
      return {
        ...state,
        user: { ...state.user, ...action.payload },
      };
    case 'CLEAR_ERROR':
      return { ...state, error: null };
    default:
      return state;
  }
};

const initialAuthState = {
  isAuthenticated: false,
  isLoading: false,
  user: null,
  error: null,
};

const AuthProvider = ({ children }) => {
  const [state, dispatch] = useReducer(authReducer, initialAuthState);

  const login = useCallback(async (credentials) => {
    dispatch({ type: 'LOGIN_START' });
    try {
      // Simulated API call
      await new Promise((resolve) => setTimeout(resolve, 1000));

      if (credentials.email === 'demo@example.com' && credentials.password === 'password') {
        const user = {
          id: '1',
          email: credentials.email,
          name: 'Demo User',
          avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=demo',
          role: 'admin',
          preferences: {
            notifications: true,
            newsletter: false,
          },
        };
        dispatch({ type: 'LOGIN_SUCCESS', payload: user });
        return { success: true, user };
      } else {
        throw new Error('Invalid email or password');
      }
    } catch (error) {
      dispatch({ type: 'LOGIN_FAILURE', payload: error.message });
      return { success: false, error: error.message };
    }
  }, []);

  const logout = useCallback(() => {
    dispatch({ type: 'LOGOUT' });
  }, []);

  const updateUser = useCallback((updates) => {
    dispatch({ type: 'UPDATE_USER', payload: updates });
  }, []);

  const clearError = useCallback(() => {
    dispatch({ type: 'CLEAR_ERROR' });
  }, []);

  const value = useMemo(
    () => ({
      ...state,
      login,
      logout,
      updateUser,
      clearError,
    }),
    [state, login, logout, updateUser, clearError]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

AuthProvider.propTypes = {
  children: PropTypes.node.isRequired,
};

/**
 * Notification Context - Global notification/toast management
 */
const NotificationContext = createContext(null);

const notificationReducer = (state, action) => {
  switch (action.type) {
    case 'ADD_NOTIFICATION':
      return {
        ...state,
        notifications: [...state.notifications, action.payload],
      };
    case 'REMOVE_NOTIFICATION':
      return {
        ...state,
        notifications: state.notifications.filter((n) => n.id !== action.payload),
      };
    case 'CLEAR_ALL':
      return { ...state, notifications: [] };
    default:
      return state;
  }
};

const NotificationProvider = ({ children, maxNotifications = 5 }) => {
  const [state, dispatch] = useReducer(notificationReducer, { notifications: [] });

  const addNotification = useCallback(
    (notification) => {
      const id = `notification-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      const newNotification = {
        id,
        type: 'info',
        duration: 5000,
        dismissible: true,
        ...notification,
        createdAt: new Date().toISOString(),
      };

      dispatch({ type: 'ADD_NOTIFICATION', payload: newNotification });

      // Auto-remove after duration
      if (newNotification.duration > 0) {
        setTimeout(() => {
          dispatch({ type: 'REMOVE_NOTIFICATION', payload: id });
        }, newNotification.duration);
      }

      // Limit notifications
      if (state.notifications.length >= maxNotifications) {
        dispatch({ type: 'REMOVE_NOTIFICATION', payload: state.notifications[0].id });
      }

      return id;
    },
    [maxNotifications, state.notifications]
  );

  const removeNotification = useCallback((id) => {
    dispatch({ type: 'REMOVE_NOTIFICATION', payload: id });
  }, []);

  const clearAll = useCallback(() => {
    dispatch({ type: 'CLEAR_ALL' });
  }, []);

  // Convenience methods
  const notify = useMemo(
    () => ({
      info: (message, options) => addNotification({ type: 'info', message, ...options }),
      success: (message, options) => addNotification({ type: 'success', message, ...options }),
      warning: (message, options) => addNotification({ type: 'warning', message, ...options }),
      error: (message, options) => addNotification({ type: 'error', message, ...options }),
    }),
    [addNotification]
  );

  const value = useMemo(
    () => ({
      notifications: state.notifications,
      addNotification,
      removeNotification,
      clearAll,
      notify,
    }),
    [state.notifications, addNotification, removeNotification, clearAll, notify]
  );

  return (
    <NotificationContext.Provider value={value}>
      {children}
    </NotificationContext.Provider>
  );
};

NotificationProvider.propTypes = {
  children: PropTypes.node.isRequired,
  maxNotifications: PropTypes.number,
};

// ============================================================================
// SECTION 3: CUSTOM HOOKS
// ============================================================================

/**
 * useLocalStorage - Persist state to localStorage with SSR safety
 */
function useLocalStorage(key, initialValue) {
  const [storedValue, setStoredValue] = useState(() => {
    if (typeof window === 'undefined') {
      return initialValue;
    }
    try {
      const item = window.localStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch (error) {
      console.warn(`Error reading localStorage key "${key}":`, error);
      return initialValue;
    }
  });

  const setValue = useCallback(
    (value) => {
      try {
        const valueToStore = value instanceof Function ? value(storedValue) : value;
        setStoredValue(valueToStore);
        if (typeof window !== 'undefined') {
          window.localStorage.setItem(key, JSON.stringify(valueToStore));
        }
      } catch (error) {
        console.warn(`Error setting localStorage key "${key}":`, error);
      }
    },
    [key, storedValue]
  );

  const removeValue = useCallback(() => {
    try {
      setStoredValue(initialValue);
      if (typeof window !== 'undefined') {
        window.localStorage.removeItem(key);
      }
    } catch (error) {
      console.warn(`Error removing localStorage key "${key}":`, error);
    }
  }, [key, initialValue]);

  return [storedValue, setValue, removeValue];
}

/**
 * useSessionStorage - Similar to useLocalStorage but for session storage
 */
function useSessionStorage(key, initialValue) {
  const [storedValue, setStoredValue] = useState(() => {
    if (typeof window === 'undefined') return initialValue;
    try {
      const item = window.sessionStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch (error) {
      return initialValue;
    }
  });

  const setValue = useCallback(
    (value) => {
      const valueToStore = value instanceof Function ? value(storedValue) : value;
      setStoredValue(valueToStore);
      if (typeof window !== 'undefined') {
        window.sessionStorage.setItem(key, JSON.stringify(valueToStore));
      }
    },
    [key, storedValue]
  );

  return [storedValue, setValue];
}

/**
 * useDebounce - Debounce a value with configurable delay
 */
function useDebounce(value, delay = 300) {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => {
      clearTimeout(handler);
    };
  }, [value, delay]);

  return debouncedValue;
}

/**
 * useThrottle - Throttle a value with configurable interval
 */
function useThrottle(value, interval = 300) {
  const [throttledValue, setThrottledValue] = useState(value);
  const lastUpdated = useRef(Date.now());

  useEffect(() => {
    const now = Date.now();
    if (now - lastUpdated.current >= interval) {
      lastUpdated.current = now;
      setThrottledValue(value);
    } else {
      const timer = setTimeout(() => {
        lastUpdated.current = Date.now();
        setThrottledValue(value);
      }, interval - (now - lastUpdated.current));
      return () => clearTimeout(timer);
    }
  }, [value, interval]);

  return throttledValue;
}

/**
 * useFetch - Generic data fetching hook with caching and error handling
 */
function useFetch(url, options = {}) {
  const {
    method = 'GET',
    body = null,
    headers = {},
    cache = true,
    retries = 3,
    retryDelay = 1000,
    transform = (data) => data,
  } = options;

  const [state, setState] = useState({
    data: null,
    isLoading: false,
    error: null,
    isValidating: false,
  });

  const cacheRef = useRef(new Map());
  const abortControllerRef = useRef(null);

  const fetchData = useCallback(async (attemptNumber = 0) => {
    // Check cache first
    if (cache && method === 'GET' && cacheRef.current.has(url)) {
      const cached = cacheRef.current.get(url);
      if (Date.now() - cached.timestamp < 60000) {
        setState((prev) => ({
          ...prev,
          data: cached.data,
          isLoading: false,
          isValidating: true,
        }));
      }
    }

    // Abort previous request
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }
    abortControllerRef.current = new AbortController();

    setState((prev) => ({ ...prev, isLoading: !prev.data, error: null }));

    try {
      const response = await fetch(url, {
        method,
        body: body ? JSON.stringify(body) : null,
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
        signal: abortControllerRef.current.signal,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const rawData = await response.json();
      const data = transform(rawData);

      // Update cache
      if (cache && method === 'GET') {
        cacheRef.current.set(url, { data, timestamp: Date.now() });
      }

      setState({ data, isLoading: false, error: null, isValidating: false });
      return data;
    } catch (error) {
      if (error.name === 'AbortError') {
        return;
      }

      if (attemptNumber < retries - 1) {
        await new Promise((resolve) => setTimeout(resolve, retryDelay));
        return fetchData(attemptNumber + 1);
      }

      setState((prev) => ({
        ...prev,
        isLoading: false,
        error: error.message,
        isValidating: false,
      }));
    }
  }, [url, method, body, headers, cache, retries, retryDelay, transform]);

  useEffect(() => {
    if (url) {
      fetchData();
    }
    return () => {
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
      }
    };
  }, [url, fetchData]);

  const refetch = useCallback(() => fetchData(), [fetchData]);

  const mutate = useCallback((newData) => {
    setState((prev) => ({ ...prev, data: newData }));
    if (cache) {
      cacheRef.current.set(url, { data: newData, timestamp: Date.now() });
    }
  }, [url, cache]);

  return { ...state, refetch, mutate };
}

/**
 * useIntersectionObserver - Observe element visibility
 */
function useIntersectionObserver(options = {}) {
  const { threshold = 0, root = null, rootMargin = '0px', freezeOnceVisible = false } = options;
  const [entry, setEntry] = useState(null);
  const [node, setNode] = useState(null);
  const frozen = useRef(false);
  const observer = useRef(null);

  useEffect(() => {
    if (frozen.current) return;

    if (observer.current) {
      observer.current.disconnect();
    }

    observer.current = new IntersectionObserver(
      ([entry]) => {
        setEntry(entry);
        if (entry.isIntersecting && freezeOnceVisible) {
          frozen.current = true;
          observer.current?.disconnect();
        }
      },
      { threshold, root, rootMargin }
    );

    if (node) {
      observer.current.observe(node);
    }

    return () => {
      if (observer.current) {
        observer.current.disconnect();
      }
    };
  }, [node, threshold, root, rootMargin, freezeOnceVisible]);

  const isVisible = entry?.isIntersecting ?? false;

  return { ref: setNode, entry, isVisible };
}

/**
 * useMediaQuery - Responsive design hook
 */
function useMediaQuery(query) {
  const [matches, setMatches] = useState(() => {
    if (typeof window !== 'undefined') {
      return window.matchMedia(query).matches;
    }
    return false;
  });

  useEffect(() => {
    if (typeof window === 'undefined') return;

    const mediaQuery = window.matchMedia(query);
    const handler = (event) => setMatches(event.matches);

    mediaQuery.addEventListener('change', handler);
    setMatches(mediaQuery.matches);

    return () => mediaQuery.removeEventListener('change', handler);
  }, [query]);

  return matches;
}

/**
 * useWindowSize - Track window dimensions
 */
function useWindowSize() {
  const [size, setSize] = useState({
    width: typeof window !== 'undefined' ? window.innerWidth : 0,
    height: typeof window !== 'undefined' ? window.innerHeight : 0,
  });

  useEffect(() => {
    const handleResize = () => {
      setSize({
        width: window.innerWidth,
        height: window.innerHeight,
      });
    };

    window.addEventListener('resize', handleResize);
    handleResize();

    return () => window.removeEventListener('resize', handleResize);
  }, []);

  return size;
}

/**
 * useOnClickOutside - Detect clicks outside element
 */
function useOnClickOutside(ref, handler, mouseEvent = 'mousedown') {
  useEffect(() => {
    const listener = (event) => {
      if (!ref.current || ref.current.contains(event.target)) {
        return;
      }
      handler(event);
    };

    document.addEventListener(mouseEvent, listener);
    document.addEventListener('touchstart', listener);

    return () => {
      document.removeEventListener(mouseEvent, listener);
      document.removeEventListener('touchstart', listener);
    };
  }, [ref, handler, mouseEvent]);
}

/**
 * useKeyPress - Detect key presses
 */
function useKeyPress(targetKey, handler, options = {}) {
  const { event = 'keydown', ctrlKey = false, shiftKey = false, altKey = false, metaKey = false } = options;

  useEffect(() => {
    const handleKeyPress = (e) => {
      if (
        e.key === targetKey &&
        (!ctrlKey || e.ctrlKey) &&
        (!shiftKey || e.shiftKey) &&
        (!altKey || e.altKey) &&
        (!metaKey || e.metaKey)
      ) {
        handler(e);
      }
    };

    window.addEventListener(event, handleKeyPress);
    return () => window.removeEventListener(event, handleKeyPress);
  }, [targetKey, handler, event, ctrlKey, shiftKey, altKey, metaKey]);
}

/**
 * usePrevious - Track previous value
 */
function usePrevious(value) {
  const ref = useRef();
  useEffect(() => {
    ref.current = value;
  }, [value]);
  return ref.current;
}

/**
 * useInterval - setInterval as a hook
 */
function useInterval(callback, delay) {
  const savedCallback = useRef(callback);

  useLayoutEffect(() => {
    savedCallback.current = callback;
  }, [callback]);

  useEffect(() => {
    if (delay === null) return;

    const id = setInterval(() => savedCallback.current(), delay);
    return () => clearInterval(id);
  }, [delay]);
}

/**
 * useTimeout - setTimeout as a hook
 */
function useTimeout(callback, delay) {
  const savedCallback = useRef(callback);

  useLayoutEffect(() => {
    savedCallback.current = callback;
  }, [callback]);

  useEffect(() => {
    if (delay === null) return;

    const id = setTimeout(() => savedCallback.current(), delay);
    return () => clearTimeout(id);
  }, [delay]);
}

/**
 * useToggle - Boolean toggle state
 */
function useToggle(initialValue = false) {
  const [value, setValue] = useState(initialValue);

  const toggle = useCallback(() => setValue((v) => !v), []);
  const setTrue = useCallback(() => setValue(true), []);
  const setFalse = useCallback(() => setValue(false), []);

  return [value, toggle, { setTrue, setFalse, setValue }];
}

/**
 * useArray - Array state management
 */
function useArray(initialArray = []) {
  const [array, setArray] = useState(initialArray);

  const push = useCallback((element) => {
    setArray((arr) => [...arr, element]);
  }, []);

  const filter = useCallback((callback) => {
    setArray((arr) => arr.filter(callback));
  }, []);

  const update = useCallback((index, newElement) => {
    setArray((arr) => arr.map((el, i) => (i === index ? newElement : el)));
  }, []);

  const remove = useCallback((index) => {
    setArray((arr) => arr.filter((_, i) => i !== index));
  }, []);

  const clear = useCallback(() => {
    setArray([]);
  }, []);

  return { array, set: setArray, push, filter, update, remove, clear };
}

/**
 * useForm - Form state and validation management
 */
function useForm(initialValues = {}, validationRules = {}) {
  const [values, setValues] = useState(initialValues);
  const [errors, setErrors] = useState({});
  const [touched, setTouched] = useState({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isValid, setIsValid] = useState(true);

  const validate = useCallback(
    (fieldName, value) => {
      const rules = validationRules[fieldName];
      if (!rules) return '';

      for (const rule of rules) {
        if (rule.required && !value) {
          return rule.message || `${fieldName} is required`;
        }
        if (rule.minLength && value.length < rule.minLength) {
          return rule.message || `${fieldName} must be at least ${rule.minLength} characters`;
        }
        if (rule.maxLength && value.length > rule.maxLength) {
          return rule.message || `${fieldName} must be at most ${rule.maxLength} characters`;
        }
        if (rule.pattern && !rule.pattern.test(value)) {
          return rule.message || `${fieldName} is invalid`;
        }
        if (rule.custom && !rule.custom(value, values)) {
          return rule.message || `${fieldName} is invalid`;
        }
      }
      return '';
    },
    [validationRules, values]
  );

  const validateAll = useCallback(() => {
    const newErrors = {};
    let valid = true;

    Object.keys(validationRules).forEach((fieldName) => {
      const error = validate(fieldName, values[fieldName]);
      if (error) {
        newErrors[fieldName] = error;
        valid = false;
      }
    });

    setErrors(newErrors);
    setIsValid(valid);
    return valid;
  }, [validationRules, values, validate]);

  const handleChange = useCallback(
    (e) => {
      const { name, value, type, checked } = e.target;
      const newValue = type === 'checkbox' ? checked : value;

      setValues((prev) => ({ ...prev, [name]: newValue }));

      if (touched[name]) {
        const error = validate(name, newValue);
        setErrors((prev) => ({ ...prev, [name]: error }));
      }
    },
    [touched, validate]
  );

  const handleBlur = useCallback(
    (e) => {
      const { name, value } = e.target;
      setTouched((prev) => ({ ...prev, [name]: true }));
      const error = validate(name, value);
      setErrors((prev) => ({ ...prev, [name]: error }));
    },
    [validate]
  );

  const handleSubmit = useCallback(
    (onSubmit) => async (e) => {
      e.preventDefault();
      setIsSubmitting(true);

      const allTouched = Object.keys(validationRules).reduce(
        (acc, key) => ({ ...acc, [key]: true }),
        {}
      );
      setTouched(allTouched);

      if (validateAll()) {
        try {
          await onSubmit(values);
        } catch (error) {
          console.error('Form submission error:', error);
        }
      }

      setIsSubmitting(false);
    },
    [values, validationRules, validateAll]
  );

  const reset = useCallback(() => {
    setValues(initialValues);
    setErrors({});
    setTouched({});
    setIsSubmitting(false);
    setIsValid(true);
  }, [initialValues]);

  const setFieldValue = useCallback((name, value) => {
    setValues((prev) => ({ ...prev, [name]: value }));
  }, []);

  const setFieldError = useCallback((name, error) => {
    setErrors((prev) => ({ ...prev, [name]: error }));
  }, []);

  return {
    values,
    errors,
    touched,
    isSubmitting,
    isValid,
    handleChange,
    handleBlur,
    handleSubmit,
    reset,
    setFieldValue,
    setFieldError,
    setValues,
  };
}

/**
 * useAsync - Async operation state management
 */
function useAsync(asyncFunction, immediate = true) {
  const [state, setState] = useState({
    status: 'idle',
    data: null,
    error: null,
  });

  const execute = useCallback(
    async (...params) => {
      setState({ status: 'pending', data: null, error: null });
      try {
        const response = await asyncFunction(...params);
        setState({ status: 'success', data: response, error: null });
        return response;
      } catch (error) {
        setState({ status: 'error', data: null, error });
        throw error;
      }
    },
    [asyncFunction]
  );

  useEffect(() => {
    if (immediate) {
      execute();
    }
  }, [execute, immediate]);

  return {
    ...state,
    execute,
    isLoading: state.status === 'pending',
    isError: state.status === 'error',
    isSuccess: state.status === 'success',
    isIdle: state.status === 'idle',
  };
}

/**
 * useClipboard - Copy to clipboard functionality
 */
function useClipboard(timeout = 2000) {
  const [copied, setCopied] = useState(false);
  const [error, setError] = useState(null);

  const copy = useCallback(
    async (text) => {
      try {
        await navigator.clipboard.writeText(text);
        setCopied(true);
        setError(null);
        setTimeout(() => setCopied(false), timeout);
      } catch (err) {
        setError(err);
        setCopied(false);
      }
    },
    [timeout]
  );

  return { copied, error, copy };
}

// ============================================================================
// SECTION 4: ERROR BOUNDARIES
// ============================================================================

/**
 * ErrorBoundary - Catch and handle component errors gracefully
 */
class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null, errorInfo: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    this.setState({ errorInfo });

    // Log to error tracking service
    if (this.props.onError) {
      this.props.onError(error, errorInfo);
    }

    console.error('ErrorBoundary caught an error:', error, errorInfo);
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
    if (this.props.onReset) {
      this.props.onReset();
    }
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback({
          error: this.state.error,
          errorInfo: this.state.errorInfo,
          reset: this.handleReset,
        });
      }

      return (
        <div
          style={{
            padding: '40px',
            textAlign: 'center',
            backgroundColor: '#fef2f2',
            borderRadius: '8px',
            border: '1px solid #fecaca',
          }}
        >
          <h2 style={{ color: '#dc2626', marginBottom: '16px' }}>Something went wrong</h2>
          <p style={{ color: '#7f1d1d', marginBottom: '24px' }}>
            {this.state.error?.message || 'An unexpected error occurred'}
          </p>
          <button
            onClick={this.handleReset}
            style={{
              padding: '10px 20px',
              backgroundColor: '#dc2626',
              color: 'white',
              border: 'none',
              borderRadius: '6px',
              cursor: 'pointer',
            }}
          >
            Try Again
          </button>
          {process.env.NODE_ENV === 'development' && this.state.errorInfo && (
            <details style={{ marginTop: '20px', textAlign: 'left' }}>
              <summary style={{ cursor: 'pointer', color: '#7f1d1d' }}>
                Error Details
              </summary>
              <pre
                style={{
                  whiteSpace: 'pre-wrap',
                  fontSize: '12px',
                  padding: '16px',
                  backgroundColor: '#fff',
                  borderRadius: '4px',
