<script setup lang="ts">
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { Icon } from '@iconify/vue';
import { useAuthStore } from '../stores/auth';

const route = useRoute();
const router = useRouter();
const authStore = useAuthStore();

const identifier = ref('');
const password = ref('');
const remember = ref(true);
const isSubmitting = ref(false);
const loginError = ref('');

const safeNext = computed(() => {
  const nextValue = Array.isArray(route.query.next)
    ? String(route.query.next[0] || '/')
    : String(route.query.next || '/');
  return nextValue.startsWith('/') ? nextValue : '/';
});

const startClubLogin = () => {
  authStore.startOAuthLogin('iOSClub', safeNext.value, remember.value);
};

const handlePasswordLogin = async () => {
  const trimmedIdentifier = identifier.value.trim();

  if (!trimmedIdentifier) {
    loginError.value = '请输入学号或账号';
    return;
  }

  if (!password.value) {
    loginError.value = '请输入密码';
    return;
  }

  isSubmitting.value = true;
  loginError.value = '';

  try {
    await authStore.loginWithProviderPassword('iOSClub', trimmedIdentifier, password.value, remember.value);
    await router.replace(safeNext.value);
  } catch (error) {
    loginError.value = error instanceof Error ? error.message : '登录失败，请稍后重试';
  } finally {
    isSubmitting.value = false;
  }
};

const handleLogout = async () => {
  await authStore.logout();
};
</script>

<template>
  <div class="min-h-screen bg-[#F6F8FC] px-4 py-12 text-[#1E293B] dark:bg-[#0F172A] dark:text-[#E5E7EB] sm:px-6 lg:px-8">
    <div class="mx-auto flex w-full max-w-5xl flex-col overflow-hidden rounded-lg border border-[#E2E8F0] bg-white shadow-sm dark:border-[#1E293B] dark:bg-[#111827] lg:grid lg:grid-cols-[0.95fr_1.05fr]">
      <!-- 左侧品牌区 -->
      <div class="relative overflow-hidden bg-[#0F172A] px-8 py-10 text-white dark:bg-[#020617] lg:px-10 lg:py-12">
        <div class="relative">
          <div class="inline-flex items-center gap-3 rounded-md bg-white/10 px-4 py-2 text-xs font-semibold text-[#93C5FD]">
            <img src="/assets/logo.png" alt="Let Coding" class="h-6 w-6" />
            Let Coding 在线评测
          </div>

          <h1 class="mt-8 text-3xl font-bold tracking-tight">登录后继续你的代码练习</h1>
          <p class="mt-5 text-base leading-8 text-slate-300">
            使用 iOSClub 账号登录，登录成功后自动回到刚才访问的页面。
          </p>

          <div class="mt-10 space-y-4">
            <div class="info-card">
              <Icon icon="material-symbols:verified-user" class="h-5 w-5 text-[#60A5FA]" />
              <span>使用 iOSClub 账号登录。</span>
            </div>
            <div class="info-card">
              <Icon icon="material-symbols:lock-open-right" class="h-5 w-5 text-[#60A5FA]" />
              <span>登录后签发本站会话，可提交代码、收藏题目、同步学习记录。</span>
            </div>
            <div class="info-card">
              <Icon icon="material-symbols:route" class="h-5 w-5 text-[#60A5FA]" />
              <span>登录后自动返回刚才访问的页面。</span>
            </div>
          </div>
        </div>
      </div>

      <!-- 右侧表单区 -->
      <div class="px-8 py-10 lg:px-10 lg:py-12">
        <div class="max-w-md">
          <p class="text-sm font-semibold text-[#2563EB] dark:text-[#60A5FA]">账号登录</p>
          <h2 class="mt-3 text-2xl font-bold tracking-tight">登录 Let Coding</h2>
          <p class="mt-3 text-sm leading-7 text-[#64748B] dark:text-[#94A3B8]">
            输入你的 iOSClub 账号和密码。
          </p>

          <div v-if="authStore.isAuthenticated" class="mt-8 rounded-md border border-emerald-200 bg-emerald-50 p-5 text-sm leading-7 text-emerald-800 dark:border-emerald-900 dark:bg-emerald-950/50 dark:text-emerald-100">
            当前已登录：<span class="font-bold">{{ authStore.displayName }}</span>。如果需要切换账号，可以先退出再重新登录。
            <div class="mt-4">
              <button class="ui-btn ui-btn-danger" @click="handleLogout">退出当前账号</button>
            </div>
          </div>

          <form class="mt-8 space-y-5" @submit.prevent="handlePasswordLogin">
            <div v-if="loginError" class="rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-700 dark:border-rose-900 dark:bg-rose-950/50 dark:text-rose-300">
              {{ loginError }}
            </div>

            <div class="relative">
              <Icon icon="material-symbols:person-rounded" class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#94A3B8]" />
              <input
                v-model="identifier"
                type="text"
                autocomplete="username"
                placeholder="学号或账号"
                class="ui-input h-12 pl-10"
              />
            </div>

            <div class="relative">
              <Icon icon="material-symbols:lock-rounded" class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#94A3B8]" />
              <input
                v-model="password"
                type="password"
                autocomplete="current-password"
                placeholder="密码"
                class="ui-input h-12 pl-10"
                @keyup.enter="handlePasswordLogin"
              />
            </div>

            <div class="flex items-center justify-between gap-4 text-sm">
              <label class="flex items-center gap-2">
                <input v-model="remember" type="checkbox" class="h-4 w-4 rounded border-[#E2E8F0] text-[#2563EB] focus:ring-[#2563EB]/30" />
                <span class="text-[#64748B] dark:text-[#94A3B8]">记住登录状态</span>
              </label>
              <span class="truncate text-xs text-[#94A3B8]">返回：{{ safeNext }}</span>
            </div>

            <button
              type="submit"
              class="ui-btn ui-btn-primary h-12 w-full text-base"
              :disabled="isSubmitting"
            >
              <Icon v-if="isSubmitting" icon="material-symbols:progress-activity" class="h-5 w-5 animate-spin" />
              <Icon v-else icon="material-symbols:login" class="h-5 w-5" />
              登录
            </button>
          </form>

          <button
            class="ui-btn ui-btn-ghost mt-4 h-12 w-full"
            @click="startClubLogin"
          >
            <Icon icon="material-symbols:open-in-new" class="h-5 w-5" />
            使用 OAuth 页面登录
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
@reference 'tailwindcss';

.info-card {
  @apply flex items-start gap-3 rounded-md border border-white/10 bg-white/5 px-4 py-4 text-sm leading-7 text-slate-200;
}
</style>
