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
import { formatDate } from '../utils/time';

defineProps<{
  items: RecentItem[];
}>();

const emit = defineEmits<{
  (e: 'open', path: string): void;
  (e: 'clear'): void;
}>();

function iconFor(name: string): string {
  const ext = name.split('.').pop()?.toLowerCase() || '';
  if (['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'bmp'].includes(ext)) return 'material-symbols:image';
  if (ext === 'pdf') return 'material-symbols:picture-as-pdf';
  if (['js', 'ts', 'py', 'c', 'cpp', 'h', 'java', 'go', 'rs', 'json'].includes(ext)) return 'material-symbols:code';
  return 'material-symbols:description';
}

function timeAgo(ts: number): string {
  if (!ts) return '未知时间';
  const diff = Date.now() - ts * 1000;
  const day = 86400000;
  if (diff < day) return '今天';
  if (diff < 2 * day) return '昨天';
  if (diff < 7 * day) return `${Math.floor(diff / day)} 天前`;
  return formatDate(ts * 1000, { month: 'short', day: 'numeric' });
}
</script>

<template>
  <div class="recent-panel">
    <div class="recent-header">
      <div class="recent-title">
        <Icon icon="material-symbols:history" class="recent-title-icon" />
        <span>最近浏览</span>
      </div>
      <button v-if="items.length" class="recent-clear" title="清空记录" @click="emit('clear')">
        <Icon icon="material-symbols:delete-outline" class="h-4 w-4" />
      </button>
    </div>

    <div v-if="items.length === 0" class="recent-empty">
      <Icon icon="material-symbols:visibility-off" class="recent-empty-icon" />
      <p>暂无浏览记录</p>
      <span>打开任意资料后会出现在这里</span>
    </div>

    <ul v-else class="recent-list">
      <li
        v-for="item in items"
        :key="item.path"
        class="recent-item"
        @click="emit('open', item.path)"
      >
        <Icon :icon="iconFor(item.path)" class="recent-item-icon" />
        <div class="recent-item-body">
          <span class="recent-item-title" :title="item.title">{{ item.title }}</span>
          <span class="recent-item-meta">{{ item.dir }} · {{ timeAgo(item.mtime) }}</span>
        </div>
        <Icon icon="material-symbols:chevron-right" class="recent-item-arrow" />
      </li>
    </ul>
  </div>
</template>

<style scoped>
.recent-panel {
  display: flex;
  flex-direction: column;
  height: 100%;
}
.recent-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 4px 12px;
  border-bottom: 1px solid var(--color-border);
  margin-bottom: 8px;
}
:global(html.dark) .recent-header { border-bottom-color: var(--color-border); }
.recent-title {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 14px;
  font-weight: 700;
  color: var(--color-foreground);
}
:global(html.dark) .recent-title { color: var(--color-foreground); }
.recent-title-icon {
  width: 18px;
  height: 18px;
  color: var(--color-accent-text);
}
.recent-clear {
  background: none;
  border: none;
  cursor: pointer;
  color: var(--color-muted-foreground);
  padding: 4px;
  border-radius: 6px;
  display: flex;
}
.recent-clear:hover { color: var(--color-danger-text); background: var(--color-danger-soft); }
:global(html.dark) .recent-clear:hover { background: var(--color-surface-muted); }

.recent-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 40px 16px;
  color: var(--color-muted-foreground);
}
.recent-empty-icon {
  width: 30px;
  height: 30px;
  margin-bottom: 8px;
  color: var(--color-foreground);
}
:global(html.dark) .recent-empty-icon { color: var(--color-muted-foreground); }
.recent-empty p {
  margin: 0;
  font-size: 13px;
  color: var(--color-muted-foreground);
  font-weight: 600;
}
:global(html.dark) .recent-empty p { color: var(--color-muted-foreground); }
.recent-empty span {
  font-size: 11px;
  margin-top: 4px;
}

.recent-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.recent-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 10px;
  border-radius: 8px;
  cursor: pointer;
  transition: background 0.13s;
}
.recent-item:hover { background: var(--color-muted); }
:global(html.dark) .recent-item:hover { background: var(--color-surface-muted); }
.recent-item-icon {
  width: 18px;
  height: 18px;
  color: var(--color-accent-text);
  flex-shrink: 0;
}
:global(html.dark) .recent-item-icon { color: var(--color-accent-text); }
.recent-item-body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.recent-item-title {
  font-size: 13px;
  color: var(--color-foreground);
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
:global(html.dark) .recent-item-title { color: var(--color-foreground); }
.recent-item-meta {
  font-size: 11px;
  color: var(--color-muted-foreground);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.recent-item-arrow {
  width: 16px;
  height: 16px;
  color: var(--color-foreground);
  flex-shrink: 0;
  opacity: 0;
  transition: opacity 0.13s;
}
.recent-item:hover .recent-item-arrow { opacity: 1; }
</style>
