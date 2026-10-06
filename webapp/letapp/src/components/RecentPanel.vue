<script lang="ts">
export interface RecentItem {
  path: string;
  title: string;
  dir: string;
  mtime: number;
  visitedAt: number;
}
</script>

<script setup lang="ts">
import { Icon } from '@iconify/vue';
import { fileIcon } from '../utils/learnFile';
import { formatRelativeTime } from '../utils/time';

defineProps<{
  items: RecentItem[];
}>();

const emit = defineEmits<{
  (e: 'open', path: string): void;
}>();
</script>

<template>
  <div class="recent-panel">
    <div v-if="items.length === 0" class="recent-empty">
      <Icon icon="material-symbols:history" class="recent-empty-icon" />
      <p>暂无浏览记录</p>
      <span>打开任意资料后会出现在这里</span>
    </div>

    <ul v-else class="recent-list">
      <li v-for="item in items" :key="item.path" class="recent-item">
        <button
          type="button"
          class="recent-item-btn"
          :title="item.title"
          @click="emit('open', item.path)"
        >
          <Icon :icon="fileIcon(item.path)" class="recent-item-icon" aria-hidden="true" />
          <span class="recent-item-body">
            <span class="recent-item-title">{{ item.title }}</span>
            <span class="recent-item-meta">{{ item.dir }} · {{ formatRelativeTime(item.mtime * 1000) }}</span>
          </span>
          <Icon
            icon="material-symbols:chevron-right"
            class="recent-item-arrow"
            aria-hidden="true"
          />
        </button>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.recent-panel {
  display: flex;
  flex-direction: column;
}

.recent-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 40px 16px;
  text-align: center;
  color: var(--color-muted-foreground);
}
.recent-empty-icon {
  width: 28px;
  height: 28px;
  margin-bottom: 8px;
  color: var(--color-border-strong);
}
.recent-empty p {
  margin: 0;
  font-size: 13px;
  font-weight: 600;
  color: var(--color-muted-foreground);
}
.recent-empty span {
  margin-top: 4px;
  font-size: 11px;
}

.recent-list {
  display: flex;
  flex-direction: column;
  gap: 1px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.recent-item-btn {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  padding: 9px 10px;
  border: none;
  border-radius: 6px;
  background: none;
  font-family: inherit;
  text-align: left;
  cursor: pointer;
  transition: background-color 0.15s ease;
}
.recent-item-btn:hover {
  background: var(--color-muted);
}

.recent-item-icon {
  width: 18px;
  height: 18px;
  flex-shrink: 0;
  color: var(--color-muted-foreground);
}

.recent-item-body {
  display: flex;
  flex: 1;
  min-width: 0;
  flex-direction: column;
  gap: 2px;
}
.recent-item-title {
  overflow: hidden;
  font-size: 13px;
  font-weight: 500;
  color: var(--color-foreground);
  text-overflow: ellipsis;
  white-space: nowrap;
}
.recent-item-meta {
  overflow: hidden;
  font-size: 11px;
  color: var(--color-muted-foreground);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.recent-item-arrow {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  color: var(--color-muted-foreground);
  opacity: 0;
  transition: opacity 0.15s ease;
}
.recent-item-btn:hover .recent-item-arrow,
.recent-item-btn:focus-visible .recent-item-arrow {
  opacity: 1;
}

@media (prefers-reduced-motion: reduce) {
  .recent-item-btn,
  .recent-item-arrow {
    transition-duration: 0.01ms;
  }
}
</style>
