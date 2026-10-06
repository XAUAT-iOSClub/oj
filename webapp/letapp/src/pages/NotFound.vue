<script setup lang="ts">
import { Icon } from '@iconify/vue';
import { useRouter } from 'vue-router';

const router = useRouter();
</script>

<template>
  <main class="grid min-h-screen place-items-center bg-[var(--color-background)] px-6 text-[var(--color-foreground)] dark:bg-[var(--color-background)] dark:text-[var(--color-foreground)]">
    <section class="w-full max-w-[480px] text-center">
      <Icon
        icon="material-symbols:search-off-rounded"
        class="mx-auto mb-4 h-16 w-16 text-[var(--color-foreground)] dark:text-[var(--color-muted-foreground)]"
      />
      <h1 class="text-[32px] font-bold">页面不存在</h1>
      <p class="mt-2 text-base text-[var(--color-muted-foreground)]">您访问的页面不存在或已被移除。</p>
      <div class="mt-8 flex items-center justify-center" style="gap:12px">
        <button class="ui-btn ui-btn-primary" @click="router.push('/')">返回首页</button>
        <button class="ui-btn ui-btn-secondary" @click="router.back()">返回上一页</button>
      </div>
    </section>
  </main>
</template>
