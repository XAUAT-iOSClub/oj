<template>
  <div class="app-shell" :style="{ '--header-h': '4rem' }">
    <a class="skip-link" href="#main-content">跳到主要内容</a>

    <header class="site-header">
      <div class="app-container header-inner">
        <a
          href="https://www.xauat.site/"
          target="_blank"
          rel="noopener"
          class="brand"
          aria-label="Let Coding 官网"
        >
          <img
            src="/assets/logo.png"
            alt=""
            width="36"
            height="36"
            class="brand-logo"
          />
          <span class="brand-name">Let Coding</span>
        </a>

        <nav class="primary-nav" aria-label="主导航">
          <router-link
            v-for="item in navItems"
            :key="item.to"
            :to="item.to"
            class="nav-link"
            :class="{ 'is-active': isActive(item.to) }"
            :aria-current="isActive(item.to) ? 'page' : undefined"
            @click="dismissMenu"
          >
            {{ item.label }}
          </router-link>
        </nav>

        <div class="header-actions">
          <form class="header-search" role="search" @submit.prevent="goSearch">
            <label class="sr-only" for="global-search">搜索题目</label>
            <Icon
              icon="material-symbols:search-rounded"
              class="header-search-icon"
              aria-hidden="true"
            />
            <input
              id="global-search"
              v-model="globalSearchQuery"
              class="header-search-input"
              type="search"
              autocomplete="off"
              placeholder="搜索题目"
            />
          </form>

          <button
            type="button"
            class="ui-icon-btn compact-only"
            aria-label="搜索题目"
            @click="router.push('/problems')"
          >
            <Icon
              icon="material-symbols:search-rounded"
              class="h-5 w-5"
              aria-hidden="true"
            />
          </button>

          <button
            type="button"
            class="ui-icon-btn"
            :aria-label="isDark ? '切换到浅色模式' : '切换到深色模式'"
            :aria-pressed="isDark"
            @click="mainToggleTheme"
          >
            <Icon
              :icon="
                isDark
                  ? 'material-symbols:dark-mode'
                  : 'material-symbols:light-mode'
              "
              class="h-5 w-5"
              aria-hidden="true"
            />
          </button>

          <button
            v-if="!authStore.isAuthenticated"
            type="button"
            class="ui-btn ui-btn-primary ui-btn-md"
            @click="startClubLogin"
          >
            登录
          </button>

          <div v-else class="user-menu-root">
            <button
              ref="userMenuButtonRef"
              type="button"
              class="ui-btn ui-btn-secondary ui-btn-md user-menu-trigger"
              aria-haspopup="menu"
              :aria-expanded="userMenuVisible"
              aria-controls="user-menu"
              @click.stop="toggleUserMenu"
            >
              <Icon
                icon="material-symbols:person-rounded"
                class="h-4 w-4"
                aria-hidden="true"
              />
              <span class="user-menu-name">{{ authStore.displayName }}</span>
              <Icon
                :icon="
                  userMenuVisible
                    ? 'material-symbols:keyboard-arrow-up'
                    : 'material-symbols:keyboard-arrow-down'
                "
                class="h-4 w-4"
                aria-hidden="true"
              />
            </button>

            <transition name="dropdown-fade">
              <div
                v-if="userMenuVisible"
                id="user-menu"
                ref="userMenuRef"
                class="ui-overlay user-menu"
                role="menu"
                aria-label="个人中心"
                @keydown="onUserMenuKeydown"
              >
                <button
                  type="button"
                  role="menuitem"
                  tabindex="-1"
                  class="user-menu-item"
                  @click="goUserPage('/profile')"
                >
                  <Icon icon="material-symbols:person-rounded" class="h-4 w-4" aria-hidden="true" />
                  <span>个人中心</span>
                </button>
                <button
                  type="button"
                  role="menuitem"
                  tabindex="-1"
                  class="user-menu-item"
                  @click="goUserPage('/submissions')"
                >
                  <Icon icon="material-symbols:history-rounded" class="h-4 w-4" aria-hidden="true" />
                  <span>题目提交记录</span>
                </button>
                <button
                  type="button"
                  role="menuitem"
                  tabindex="-1"
                  class="user-menu-item"
                  @click="goUserPage('/favorites')"
                >
                  <Icon icon="material-symbols:star-rounded" class="h-4 w-4" aria-hidden="true" />
                  <span>收藏题目</span>
                </button>
                <hr class="ui-divider my-1" />
                <button
                  type="button"
                  role="menuitem"
                  tabindex="-1"
                  class="user-menu-item user-menu-danger"
                  @click="handleLogout"
                >
                  <Icon icon="material-symbols:logout" class="h-4 w-4" aria-hidden="true" />
                  <span>退出登录</span>
                </button>
              </div>
            </transition>
          </div>

          <button
            ref="menuButtonRef"
            type="button"
            class="ui-icon-btn nav-toggle"
            aria-label="打开导航菜单"
            aria-haspopup="dialog"
            :aria-expanded="menuVisible"
            aria-controls="mobile-nav"
            @click.stop="toggleMobileMenu"
          >
            <Icon
              :icon="
                menuVisible
                  ? 'material-symbols:close-rounded'
                  : 'material-symbols:menu-rounded'
              "
              class="h-6 w-6"
              aria-hidden="true"
            />
          </button>
        </div>
      </div>
    </header>

    <transition name="drawer-backdrop">
      <div
        v-if="menuVisible"
        class="drawer-backdrop"
        @click="dismissMenu"
      ></div>
    </transition>

    <transition name="drawer-slide">
      <aside
        v-if="menuVisible"
        id="mobile-nav"
        ref="drawerRef"
        class="mobile-drawer"
        role="dialog"
        aria-modal="true"
        aria-label="导航菜单"
        @keydown="onDrawerKeydown"
      >
        <div class="drawer-heading">
          <div class="drawer-brand">
            <img src="/assets/logo.png" alt="" width="40" height="40" class="brand-logo" />
            <div>
              <div class="drawer-brand-name">Let Coding</div>
              <div class="drawer-brand-sub">在线评测</div>
            </div>
          </div>
          <button
            ref="drawerCloseRef"
            type="button"
            class="ui-icon-btn"
            aria-label="关闭导航菜单"
            @click="dismissMenu"
          >
            <Icon icon="material-symbols:close-rounded" class="h-5 w-5" aria-hidden="true" />
          </button>
        </div>

        <nav class="drawer-nav" aria-label="移动端导航">
          <router-link
            v-for="item in navItems"
            :key="`${item.to}-menu`"
            :to="item.to"
            class="drawer-link"
            :class="{ 'is-active': isActive(item.to) }"
            :aria-current="isActive(item.to) ? 'page' : undefined"
            @click="dismissMenu"
          >
            {{ item.label }}
          </router-link>
        </nav>
      </aside>
    </transition>

    <main id="main-content" class="app-main" tabindex="-1">
      <router-view v-slot="{ Component, route }">
        <transition name="page-shift" mode="out-in">
          <component :is="Component" :key="route.path" />
        </transition>
      </router-view>
    </main>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { Icon } from "@iconify/vue";
import { storeToRefs } from "pinia";
import { useThemeStore } from "../stores/theme";
import { useAuthStore } from "../stores/auth";

const navItems = [
  { label: "首页", to: "/" },
  { label: "题库", to: "/problems" },
  { label: "学习", to: "/learn" },
  { label: "在线编辑器", to: "/playground" },
  { label: "比赛", to: "/contests" },
  { label: "排行榜", to: "/rankings" },
  { label: "讨论", to: "/discussion" },
  { label: "公告", to: "/announcements" },
];

const router = useRouter();
const themeStore = useThemeStore();
const authStore = useAuthStore();
const { isDark } = storeToRefs(themeStore);
const { toggleTheme } = themeStore;

const menuVisible = ref(false);
const userMenuVisible = ref(false);
const globalSearchQuery = ref("");

const drawerRef = ref<HTMLElement | null>(null);
const drawerCloseRef = ref<HTMLButtonElement | null>(null);
const menuButtonRef = ref<HTMLButtonElement | null>(null);
const userMenuRef = ref<HTMLElement | null>(null);
const userMenuButtonRef = ref<HTMLButtonElement | null>(null);

const goSearch = () => {
  const q = globalSearchQuery.value.trim();
  if (!q) return;
  void router.push({ path: "/problems", query: { q } });
  globalSearchQuery.value = "";
};

const currentPath = computed(() => router.currentRoute.value.path);
const isActive = (to: string) =>
  to === "/" ? currentPath.value === "/" : currentPath.value.startsWith(to);

/* ---------- 移动端抽屉 ---------- */
const menuTriggerWasFocused = ref(false);

const openMenu = () => {
  menuTriggerWasFocused.value = true;
  menuVisible.value = true;
};

const closeMenu = (restoreFocus = false) => {
  if (!menuVisible.value) return;
  menuVisible.value = false;
  document.body.style.overflow = "";
  if (restoreFocus && menuTriggerWasFocused.value) {
    void nextTick(() => menuButtonRef.value?.focus());
  }
};

// 模板点击处理器：关闭抽屉并把焦点还给触发按钮
const dismissMenu = () => closeMenu(true);

const toggleMobileMenu = () => {
  if (menuVisible.value) closeMenu(true);
  else openMenu();
};

const restoreDrawerFocus = () =>
  drawerCloseRef.value?.focus({ preventScroll: true });

if (typeof window !== "undefined") {
  watch(menuVisible, (open) => {
    document.body.style.overflow = open ? "hidden" : "";
    if (open) void nextTick(restoreDrawerFocus);
  });
}

const focusablesIn = (root: HTMLElement | null) =>
  Array.from(
    root?.querySelectorAll<HTMLElement>(
      'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
    ) ?? [],
  );

const onDrawerKeydown = (event: KeyboardEvent) => {
  if (event.key !== "Tab") return;
  const items = focusablesIn(drawerRef.value);
  const first = items[0];
  const last = items[items.length - 1];
  if (!first || !last) return;
  const active = document.activeElement;
  if (event.shiftKey && active === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && active === last) {
    event.preventDefault();
    first.focus();
  }
};

/* ---------- 用户菜单 ---------- */
const userMenuItems = () =>
  Array.from(
    userMenuRef.value?.querySelectorAll<HTMLButtonElement>('[role="menuitem"]') ?? [],
  );

const openUserMenu = async () => {
  userMenuVisible.value = true;
  await nextTick();
  userMenuItems()[0]?.focus({ preventScroll: true });
};

const closeUserMenu = (restoreFocus = false) => {
  if (!userMenuVisible.value) return;
  userMenuVisible.value = false;
  if (restoreFocus) {
    void nextTick(() => userMenuButtonRef.value?.focus({ preventScroll: true }));
  }
};

const toggleUserMenu = () => {
  if (userMenuVisible.value) closeUserMenu(true);
  else void openUserMenu();
};

const onUserMenuKeydown = (event: KeyboardEvent) => {
  if (event.key === "Escape") {
    event.preventDefault();
    closeUserMenu(true);
    return;
  }
  if (event.key === "Tab") {
    // 菜单采用 roving focus，Tab 离开即收起菜单
    userMenuVisible.value = false;
    return;
  }
  if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
  const items = userMenuItems();
  if (!items.length) return;
  event.preventDefault();
  const index = items.indexOf(document.activeElement as HTMLButtonElement);
  const nextIndex =
    event.key === "Home"
      ? 0
      : event.key === "End"
        ? items.length - 1
        : event.key === "ArrowDown"
          ? (index + 1 + items.length) % items.length
          : (index - 1 + items.length) % items.length;
  items[nextIndex]?.focus();
};

/* ---------- 全局 ---------- */
const handleEscape = (event: KeyboardEvent) => {
  if (event.key !== "Escape") return;
  closeUserMenu(true);
  closeMenu(true);
};

const handleDocumentPointerDown = (event: PointerEvent) => {
  if (!userMenuVisible.value) return;
  const target = event.target as Node | null;
  if (!target) return;
  if (
    userMenuRef.value?.contains(target) ||
    userMenuButtonRef.value?.contains(target)
  ) {
    return;
  }
  closeUserMenu(false);
};

const mainToggleTheme = () => {
  toggleTheme();
};

const startClubLogin = () => {
  closeMenu();
  void authStore.startOAuthLogin(
    "iOSClub",
    router.currentRoute.value.fullPath,
    true,
  );
};

const handleLogout = async () => {
  closeMenu();
  closeUserMenu(false);
  await authStore.logout();
};

const goUserPage = async (to: string) => {
  closeUserMenu(false);
  await router.push(to);
};

let desktopQuery: MediaQueryList | null = null;
const handleDesktopChange = (event: MediaQueryListEvent) => {
  if (event.matches) closeMenu();
};

onMounted(() => {
  document.addEventListener("pointerdown", handleDocumentPointerDown, true);
  window.addEventListener("keydown", handleEscape);
  desktopQuery = window.matchMedia("(min-width: 1024px)");
  desktopQuery.addEventListener("change", handleDesktopChange);
});

onUnmounted(() => {
  document.removeEventListener("pointerdown", handleDocumentPointerDown, true);
  window.removeEventListener("keydown", handleEscape);
  desktopQuery?.removeEventListener("change", handleDesktopChange);
  document.body.style.overflow = "";
});
</script>

<style scoped>
@reference "tailwindcss";

.app-shell {
  min-height: 100vh;
  background: var(--color-background);
  color: var(--color-foreground);
  transition: background-color 0.25s ease;
}

.skip-link {
  @apply fixed left-4 top-4 z-100 -translate-y-24 px-4 py-2 text-sm font-semibold transition-transform focus-visible:translate-y-0;
  border-radius: var(--radius-card);
  background: var(--color-accent-solid);
  color: var(--color-accent-foreground);
}

/* ---------- 顶栏：固定 64px ---------- */
.site-header {
  @apply fixed inset-x-0 top-0 z-50 h-[var(--header-h,4rem)] border-b;
  border-color: var(--color-border);
  background: var(--color-surface);
}
.header-inner {
  @apply flex h-full items-center gap-3;
}

.brand {
  @apply flex shrink-0 items-center gap-2.5 py-2 pr-2 transition-opacity hover:opacity-80;
  border-radius: var(--radius-card);
}
.brand-logo {
  @apply h-9 w-9 object-cover;
  border-radius: var(--radius-card);
}
.brand-name {
  @apply text-[17px] font-semibold tracking-[-0.015em];
  color: var(--color-foreground);
}

.primary-nav {
  @apply ml-2 hidden shrink items-center gap-0.5 lg:flex;
}
.nav-link {
  @apply relative inline-flex h-11 items-center whitespace-nowrap px-3 text-sm font-medium transition-colors duration-150;
  border-radius: var(--radius-card);
  color: var(--color-muted-foreground);
}
.nav-link:hover {
  background: var(--color-muted);
  color: var(--color-foreground);
}
/* 当前路由：字重 + 短底线 + 轻度背景，三重信号而非仅颜色 */
.nav-link.is-active {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
  font-weight: 600;
}
.nav-link.is-active::after {
  content: "";
  @apply absolute bottom-1.5 left-1/2 h-0.5 w-4 -translate-x-1/2 rounded-full;
  background: var(--color-accent);
}

.header-actions {
  @apply ml-auto flex items-center gap-2;
}

.header-search {
  @apply relative hidden xl:block;
}
.header-search-icon {
  @apply pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2;
  color: var(--color-muted-foreground);
}
.header-search-input {
  @apply h-11 w-52 border pl-9 pr-3 text-sm outline-none transition-colors;
  border-radius: var(--radius-card);
  border-color: var(--color-input);
  background: var(--color-surface);
  color: var(--color-foreground);
}
.header-search-input::placeholder {
  color: var(--color-muted-foreground);
}
.header-search-input::-webkit-search-cancel-button {
  appearance: none;
}
.header-search-input:hover {
  border-color: var(--color-foreground);
}
.header-search-input:focus {
  border-color: var(--color-accent);
  box-shadow: 0 0 0 3px var(--color-accent-soft);
}

.compact-only {
  @apply xl:hidden;
}
.nav-toggle {
  @apply lg:hidden;
}

.user-menu-root {
  @apply relative;
}
.user-menu-trigger {
  @apply px-3;
}
.user-menu-name {
  @apply max-w-[8rem] truncate;
}

.user-menu {
  @apply absolute right-0 top-[calc(100%+0.5rem)] z-60 grid min-w-[13rem] gap-0.5;
}
.user-menu-item {
  @apply flex w-full items-center gap-2.5 px-3 py-2.5 text-left text-sm font-medium transition-colors;
  border-radius: var(--radius-card);
  color: var(--color-foreground);
}
.user-menu-item:hover {
  background: var(--color-muted);
}
.user-menu-item:focus-visible {
  background: var(--color-accent-soft);
  color: var(--color-accent-soft-foreground);
  outline-offset: -2px;
}
.user-menu-danger {
  color: var(--color-danger-text);
}
.user-menu-danger:hover,
.user-menu-danger:focus-visible {
  background: var(--color-danger-soft);
  color: var(--color-danger-soft-foreground);
}

.dropdown-fade-enter-active,
.dropdown-fade-leave-active {
  transition:
    opacity 0.16s ease,
    transform 0.16s ease;
}
.dropdown-fade-enter-from,
.dropdown-fade-leave-to {
  opacity: 0;
  transform: translateY(-4px);
}

/* ---------- 移动抽屉 ---------- */
.drawer-backdrop {
  @apply fixed inset-0 z-40 bg-black/40 lg:hidden;
}
.mobile-drawer {
  @apply fixed right-0 top-0 z-50 flex h-full w-[20rem] max-w-[88vw] flex-col border-l lg:hidden;
  border-color: var(--color-border);
  background: var(--color-surface);
  box-shadow: var(--shadow-overlay);
}
.drawer-heading {
  @apply flex h-16 shrink-0 items-center justify-between border-b px-3;
  border-color: var(--color-border);
}
.drawer-brand {
  @apply flex items-center gap-3;
}
.drawer-brand-name {
  @apply text-sm font-semibold;
}
.drawer-brand-sub {
  @apply text-[11px];
  color: var(--color-muted-foreground);
}
.drawer-nav {
  @apply grid content-start gap-0.5 overflow-y-auto p-3;
}
.drawer-link {
  @apply flex min-h-12 w-full items-center px-3 text-sm font-medium transition-colors;
  border-radius: var(--radius-card);
  color: var(--color-muted-foreground);
}
.drawer-link:hover {
  background: var(--color-muted);
  color: var(--color-foreground);
}
.drawer-link.is-active {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
  font-weight: 600;
  box-shadow: inset 2px 0 0 var(--color-accent);
}

.drawer-slide-enter-active,
.drawer-slide-leave-active {
  transition: transform 0.2s cubic-bezier(0.2, 0.8, 0.2, 1);
}
.drawer-slide-enter-from,
.drawer-slide-leave-to {
  transform: translateX(100%);
}
.drawer-backdrop-enter-active,
.drawer-backdrop-leave-active {
  transition: opacity 0.2s ease;
}
.drawer-backdrop-enter-from,
.drawer-backdrop-leave-to {
  opacity: 0;
}

.app-main {
  @apply pt-16 outline-none;
}

/* 窄屏：顶栏四个 44px 控件 + 品牌文字会超出视口，仅保留图标 */
@media (max-width: 480px) {
  .brand-name {
    display: none;
  }
}

@media (prefers-reduced-motion: reduce) {
  .app-shell,
  .nav-link,
  .user-menu-item,
  .drawer-link {
    transition-duration: 0.01ms !important;
  }
  .dropdown-fade-enter-active,
  .dropdown-fade-leave-active,
  .drawer-slide-enter-active,
  .drawer-slide-leave-active,
  .drawer-backdrop-enter-active,
  .drawer-backdrop-leave-active {
    transition-duration: 0.01ms;
  }
  .dropdown-fade-enter-from,
  .dropdown-fade-leave-to,
  .drawer-slide-enter-from,
  .drawer-slide-leave-to {
    transform: none;
  }
}
</style>
