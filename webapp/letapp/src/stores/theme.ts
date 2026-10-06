import { computed, ref } from 'vue';
import { defineStore } from 'pinia';
import { darkTheme } from 'naive-ui';
import { getAuthStorage, updateUserTheme } from '../services/api';

type ThemePreference = 'light' | 'dark' | 'system';
const THEME_STORAGE_KEY = 'appThemePreference';

// 无已保存偏好时默认浅色；已明确选择浅色/深色的用户不受系统主题影响。
const DEFAULT_THEME_PREFERENCE: ThemePreference = 'light';

const readThemePreference = (): ThemePreference => {
  try {
    const preference = localStorage.getItem(THEME_STORAGE_KEY);
    return preference === 'light' || preference === 'dark' || preference === 'system'
      ? preference
      : DEFAULT_THEME_PREFERENCE;
  } catch {
    return DEFAULT_THEME_PREFERENCE;
  }
};

const saveThemePreference = (preference: ThemePreference) => {
  try {
    localStorage.setItem(THEME_STORAGE_KEY, preference);
  } catch {
    // Private and embedded browsers can disable web storage.
  }
};

const getSystemPrefersDark = () => {
  try {
    return typeof window.matchMedia === 'function'
      && window.matchMedia('(prefers-color-scheme: dark)').matches;
  } catch {
    return false;
  }
};

const syncThemeToBackend = async (preference: ThemePreference) => {
  try {
    if (getAuthStorage().getItem('access_token')) {
      await updateUserTheme(preference);
    }
  } catch {
    // Silently ignore backend sync failures
  }
};

export const useThemeStore = defineStore('theme', () => {
  const userPreference = ref<ThemePreference>(readThemePreference());
  const systemPrefersDark = ref(getSystemPrefersDark());

  const updateThemeClass = (dark: boolean) => {
    document.documentElement.classList.toggle('dark', dark);
    // 让移动端浏览器地址栏与页面底色保持一致
    document
      .querySelector('meta[name="theme-color"]')
      ?.setAttribute('content', dark ? '#080b10' : '#f6f7f9');
  };

  const isDark = computed({
    get() {
      if (userPreference.value === 'dark') {
        return true;
      }

      if (userPreference.value === 'light') {
        return false;
      }

      return systemPrefersDark.value;
    },
    set(value: boolean) {
      userPreference.value = value ? 'dark' : 'light';
      saveThemePreference(userPreference.value);
      updateThemeClass(value);
      syncThemeToBackend(userPreference.value);
    },
  });

  const theme = computed(() => (isDark.value ? darkTheme : null));

  const applyUserTheme = (preference?: string) => {
    if (preference && ['light', 'dark', 'system'].includes(preference)) {
      userPreference.value = preference as ThemePreference;
      saveThemePreference(userPreference.value);
      updateThemeClass(isDark.value);
    }
  };

  const setThemePreference = (preference: ThemePreference) => {
    userPreference.value = preference;
    saveThemePreference(preference);
    updateThemeClass(isDark.value);
    syncThemeToBackend(preference);
  };

  const toggleTheme = () => {
    isDark.value = !isDark.value;
  };

  const init = () => {
    if (typeof window.matchMedia !== 'function') {
      updateThemeClass(isDark.value);
      return;
    }
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    const handleChange = (event: MediaQueryListEvent) => {
      systemPrefersDark.value = event.matches;
      if (userPreference.value === 'system') {
        updateThemeClass(isDark.value);
      }
    };
    if (typeof mediaQuery.addEventListener === 'function') {
      mediaQuery.addEventListener('change', handleChange);
    } else {
      mediaQuery.addListener(handleChange);
    }

    updateThemeClass(isDark.value);
  };

  return {
    isDark,
    theme,
    userPreference,
    applyUserTheme,
    setThemePreference,
    toggleTheme,
    init,
  };
});
