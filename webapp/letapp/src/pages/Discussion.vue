<script setup lang="ts">
import { ref, defineAsyncComponent, onMounted, onUnmounted, nextTick, watch, computed } from 'vue';
import { Icon } from '@iconify/vue';
import { useAuthStore } from '../stores/auth';
import { useRouter } from 'vue-router';
import {
  listDiscussions, listDiscussionReplies, getDiscussion, createDiscussion,
  likeDiscussion, replyToDiscussion, likeDiscussionReply,
  deleteDiscussion, deleteDiscussionReply,
  type DiscussionData, type DiscussionReplyData,
} from '../services/api';
import { formatDate, formatDateTime } from '../utils/time';

const MarkdownComponent = defineAsyncComponent(
  () => import('../components/MarkdownComponent.vue'),
);

const authStore = useAuthStore();
const router = useRouter();

const currentUserId = computed(() => Number(authStore.userInfo?.id) || 0);
const isManager = computed(() => authStore.userRole === 'manager');
// 当前用户是否能删除某条内容：作者本人或管理员（manager）
const canDeleteDiscussion = (authorId?: number) =>
  isManager.value || (authorId !== undefined && authorId === currentUserId.value);

const discussions = ref<DiscussionData[]>([]);
const isLoading = ref(false);
const error = ref('');
const activeCategory = ref('全部');

// 详情弹窗
const showDetail = ref(false);
const currentDiscussion = ref<DiscussionData | null>(null);
const detailLoading = ref(false);
const newReply = ref('');
const submittingReply = ref(false);

// 发布弹窗
const showCreate = ref(false);
const createForm = ref({ title: '', content: '', category: '问答', tags: '' });
const submitting = ref(false);

const categories = ['全部', '问答', '分享', '闲聊', '综合'];
const categoryIcons: Record<string, string> = {
  '全部': 'material-symbols:apps',
  '问答': 'material-symbols:help',
  '分享': 'material-symbols:share',
  '闲聊': 'material-symbols:chat-bubble',
  '综合': 'material-symbols:article',
};

const tagColors: Record<string, string> = {
  '动态规划': 'bg-accent-soft text-accent-text',
  '算法': 'bg-emerald-50 text-emerald-600 dark:bg-emerald-950/40 dark:text-emerald-400',
  'C++': 'bg-violet-50 text-violet-600 dark:bg-violet-950/40 dark:text-violet-400',
  '学习': 'bg-amber-50 text-amber-600 dark:bg-amber-950/40 dark:text-amber-400',
  '周赛': 'bg-rose-50 text-rose-600 dark:bg-rose-950/40 dark:text-rose-400',
  '讨论': 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300',
  '图论': 'bg-accent-soft text-accent-text',
  '模板': 'bg-pink-50 text-pink-600 dark:bg-pink-950/40 dark:text-pink-400',
};

const getTags = (tags: string | null) => {
  if (!tags) return [];
  return tags.split(',').map(t => t.trim()).filter(Boolean);
};

const LIST_TAG_LIMIT = 2;
const visibleTags = (tags: string | null) => getTags(tags).slice(0, LIST_TAG_LIMIT);
const extraTagCount = (tags: string | null) => Math.max(0, getTags(tags).length - LIST_TAG_LIMIT);

const filteredDiscussions = computed(() => {
  if (activeCategory.value === '全部') return discussions.value;
  return discussions.value.filter(d => d.category === activeCategory.value);
});

const formatTime = (dateStr?: string) => {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return '';
  const now = new Date();
  const diff = now.getTime() - d.getTime();
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(diff / 3600000);
  const days = Math.floor(diff / 86400000);
  if (minutes < 1) return '刚刚';
  if (minutes < 60) return `${minutes} 分钟前`;
  if (hours < 24) return `${hours} 小时前`;
  if (days < 7) return `${days} 天前`;
  return formatDate(d, { month: 'short', day: 'numeric' });
};

const formatFullTime = (dateStr?: string) => {
  if (!dateStr) return '';
  return formatDateTime(dateStr, {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  });
};

// ===== 数据加载 =====
let pageAbort = new AbortController();
let hasMore = true;
let listOffset = 0;
let repliesOffset = 0;
let loadingMore = false;
const loadData = async () => {
  pageAbort.abort(); pageAbort = new AbortController();
  const signal = pageAbort.signal;
  isLoading.value = true; error.value = ''; hasMore = true;
  try {
    const rows = await listDiscussions(activeCategory.value, 0, signal);
    if (signal.aborted) return;
    discussions.value = rows; listOffset = rows.length; hasMore = rows.length === 30;
  } catch (e) {
    if (!signal.aborted) error.value = e instanceof Error ? e.message : '加载失败';
  } finally {
    if (!signal.aborted) { isLoading.value = false; await nextTick(); checkMore(); }
  }
};
const checkMore = async () => {
  if (loadingMore || isLoading.value || !hasMore || error.value || showDetail.value) return;
  if (document.documentElement.scrollHeight - window.scrollY - window.innerHeight > 500) return;
  loadingMore = true;
  const signal = pageAbort.signal;
  try {
    const rows = await listDiscussions(activeCategory.value, listOffset, signal);
    if (signal.aborted) return;
    listOffset += rows.length;
    hasMore = rows.length === 30;
    const known = new Set(discussions.value.map(row => row.id));
    discussions.value.push(...rows.filter(row => !known.has(row.id)));
  } catch { /* 下一次滚动可重试，已有列表保持可用。 */ }
  finally { loadingMore = false; }
};
let repliesLoading = false;
const onScroll = async (event: Event) => {
  if (!showDetail.value) { void checkMore(); return; }
  const node = event.target;
  const current = currentDiscussion.value;
  if (!(node instanceof HTMLElement) || repliesLoading || !current || detailLoading.value) return;
  if (node.scrollHeight - node.scrollTop - node.clientHeight > 400) return;
  if ((current.replies?.length || 0) >= current.reply_count) return;
  repliesLoading = true;
  try {
    const rows = await listDiscussionReplies(current.id, repliesOffset, pageAbort.signal);
    if (currentDiscussion.value?.id !== current.id) return;
    repliesOffset += rows.length;
    const known = new Set(current.replies?.map(row => row.id));
    (current.replies ||= []).push(...rows.filter(row => !known.has(row.id)));
  } catch { /* 后续滚动重试。 */ }
  finally { repliesLoading = false; }
};
watch(activeCategory, loadData);

// ===== 查看详情 =====
const openDetail = async (d: DiscussionData) => {
  showDetail.value = true;
  detailLoading.value = true;
  try {
    const detail = await getDiscussion(d.id);
    if (!showDetail.value) return;
    currentDiscussion.value = detail; repliesOffset = detail.replies?.length || 0;
  } catch {
    currentDiscussion.value = d;
  } finally {
    detailLoading.value = false;
  }
};

const closeDetail = () => {
  showDetail.value = false;
  currentDiscussion.value = null;
  newReply.value = '';
};

// ===== 点赞 =====
const goLogin = () => {
  authStore.startOAuthLogin('iOSClub', router.currentRoute.value.fullPath, true);
};

const toggleLike = async (d: DiscussionData) => {
  if (!authStore.isAuthenticated) { goLogin(); return; }
  try {
    const res = await likeDiscussion(d.id, !d.is_liked);
    d.like_count = res.like_count;
    d.is_liked = res.liked;
  } catch {}
};

const toggleReplyLike = async (r: DiscussionReplyData) => {
  if (!authStore.isAuthenticated) { goLogin(); return; }
  try {
    const res = await likeDiscussionReply(r.id, !r.is_liked);
    r.like_count = res.like_count;
    r.is_liked = res.liked;
  } catch {};
};

// ===== 删除（管理员可删除任意内容，作者可删除自己的） =====
const deleteDiscussionById = async (discussionId: number) => {
  if (!window.confirm('确定删除该讨论吗？此操作不可撤销。')) return;
  try {
    await deleteDiscussion(discussionId);
    discussions.value = discussions.value.filter((d) => d.id !== discussionId);
    if (currentDiscussion.value?.id === discussionId) closeDetail();
  } catch (e) {
    alert(e instanceof Error ? e.message : '删除失败');
  }
};

const deleteReplyById = async (reply: DiscussionReplyData) => {
  if (!window.confirm('确定删除该回复吗？此操作不可撤销。')) return;
  try {
    await deleteDiscussionReply(reply.id);
    const replies = currentDiscussion.value?.replies;
    if (replies) {
      const idx = replies.findIndex((x) => x.id === reply.id);
      if (idx >= 0) replies.splice(idx, 1);
    }
    if (currentDiscussion.value) {
      currentDiscussion.value.reply_count = Math.max(
        0,
        (currentDiscussion.value.reply_count || 0) - 1,
      );
    }
  } catch (e) {
    alert(e instanceof Error ? e.message : '删除失败');
  }
};

// ===== 回复 =====
const submitReply = async () => {
  if (!authStore.isAuthenticated) { goLogin(); return; }
  if (!currentDiscussion.value || !newReply.value.trim()) return;
  submittingReply.value = true;
  try {
    const reply = await replyToDiscussion(currentDiscussion.value.id, newReply.value.trim());
    if (!currentDiscussion.value.replies) currentDiscussion.value.replies = [];
    currentDiscussion.value.replies.push(reply);
    currentDiscussion.value.reply_count = (currentDiscussion.value.reply_count || 0) + 1;
    newReply.value = '';
  } catch (e) {
    alert(e instanceof Error ? e.message : '回复失败');
  } finally {
    submittingReply.value = false;
  }
};

// ===== 发布 =====
const openCreate = () => {
  if (!authStore.isAuthenticated) { goLogin(); return; }
  createForm.value = { title: '', content: '', category: '问答', tags: '' };
  showCreate.value = true;
};

const submitCreate = async () => {
  if (!createForm.value.title.trim() || !createForm.value.content.trim()) return;
  submitting.value = true;
  try {
    const d = await createDiscussion(createForm.value);
    discussions.value.unshift(d);
    showCreate.value = false;
  } catch (e) {
    alert(e instanceof Error ? e.message : '发布失败');
  } finally {
    submitting.value = false;
  }
};

onMounted(() => { void loadData(); document.addEventListener('scroll', onScroll, { capture: true, passive: true }); });
onUnmounted(() => { pageAbort.abort(); document.removeEventListener('scroll', onScroll, true); });
</script>

<template>
  <div class="min-h-[calc(100vh-var(--header-h,4rem))] bg-[var(--color-background)]">
    <div class="app-container-with-sidebar py-6">
      <!-- 左侧分类 -->
      <aside class="app-sidebar-col">
         <div class="border-l border-[var(--color-border)] pl-3 dark:border-[var(--color-border)]">
          <button
            v-for="cat in categories"
            :key="cat"
            class="flex w-full items-center gap-3 rounded-lg px-4 py-3 text-left text-sm font-semibold transition"
            :class="activeCategory === cat
              ? 'bg-[var(--color-accent-soft)] text-[var(--color-accent-text)] dark:bg-[var(--color-accent-soft)] dark:text-[var(--color-accent-text)]'
              : 'text-[var(--color-muted-foreground)] hover:bg-[var(--color-muted)] dark:text-[var(--color-muted-foreground)] dark:hover:bg-[var(--color-surface-muted)]'"
            @click="activeCategory = cat"
          >
            <span class="cat-ico shrink-0 w-7 text-center"><Icon :icon="categoryIcons[cat] ?? ''" /></span>
            <span class="flex-1">{{ cat }}</span>
          </button>
        </div>
      </aside>

      <!-- 右侧内容 -->
      <section class="min-w-0 flex-1">
        <div class="mb-4 flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold text-[var(--color-foreground)]">讨论区</h1>
            <p class="ui-section-sub mt-1">交流算法心得，分享学习经验</p>
          </div>
           <button class="ui-btn ui-btn-primary ui-btn-md" @click="openCreate">
             <span class="inline-flex items-center gap-1.5"><Icon icon="material-symbols:add-comment-rounded" class="h-5 w-5" />发布讨论</span>
          </button>
        </div>

        <!-- 加载中 -->
        <div v-if="isLoading" class="space-y-3">
          <div v-for="i in 4" :key="i" class="ui-skeleton h-24 w-full rounded-md"></div>
        </div>

        <!-- 错误 -->
        <div v-else-if="error" class="ui-empty">
          <Icon icon="material-symbols:error-outline-rounded" class="mb-2 h-12 w-12 text-rose-500" />
          <p class="font-bold text-[var(--color-foreground)]">加载失败</p>
          <button class="ui-btn ui-btn-secondary ui-btn-sm mt-2" @click="loadData">重试</button>
        </div>

        <!-- 讨论列表 -->
        <div v-else class="space-y-2">
          <div
            v-for="d in filteredDiscussions"
            :key="d.id"
             class="flex cursor-pointer items-start gap-4 border-b border-[var(--color-border)] px-2 py-3 transition-colors hover:bg-[var(--color-accent-soft)] dark:border-[var(--color-border)] dark:hover:bg-[var(--color-accent-soft)]"
            @click="openDetail(d)"
          >
            <div class="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[var(--color-accent-soft)] text-[var(--color-accent-text)] dark:bg-[var(--color-accent-soft)] dark:text-[var(--color-accent-text)]">
              <Icon icon="material-symbols:person" class="h-5 w-5" />
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                 <span v-if="d.is_pinned" class="ui-badge ui-badge-amber inline-flex items-center gap-1 text-[10px]"><Icon icon="material-symbols:push-pin" class="h-3 w-3" />置顶</span>
                <h3 class="font-bold text-[var(--color-foreground)]">{{ d.title }}</h3>
              </div>
              <div v-if="getTags(d.tags).length" class="mt-1.5 flex flex-wrap items-center gap-1.5">
                <span v-for="tag in visibleTags(d.tags)" :key="tag" class="rounded-md px-2 py-0.5 text-[11px] font-medium" :class="tagColors[tag] || 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300'">{{ tag }}</span>
                <span v-if="extraTagCount(d.tags)" class="rounded-md bg-slate-100 px-2 py-0.5 text-[11px] font-medium text-slate-500 dark:bg-slate-800 dark:text-slate-400">+{{ extraTagCount(d.tags) }}</span>
              </div>
              <p class="mt-2 text-xs text-[var(--color-muted-foreground)]">{{ d.author_name }} · {{ formatTime(d.created_at) }}</p>
            </div>
            <div class="shrink-0 flex flex-col items-end gap-1 text-[var(--color-muted-foreground)]">
              <button
                class="flex items-center gap-1 text-xs font-bold transition hover:text-[var(--color-accent-text)]"
                :class="d.is_liked ? 'text-[var(--color-accent-text)]' : ''"
                @click.stop="toggleLike(d)"
              >
                 <Icon :icon="d.is_liked ? 'material-symbols:favorite' : 'material-symbols:favorite-outline'" class="h-4 w-4" />
                {{ d.like_count || 0 }}
              </button>
               <span class="inline-flex items-center gap-1 text-xs font-bold"><Icon icon="material-symbols:chat-bubble-outline" class="h-3.5 w-3.5" />{{ d.reply_count || 0 }}</span>
               <span class="inline-flex items-center gap-1 text-[10px] text-[var(--color-muted-foreground)]"><Icon icon="material-symbols:visibility" class="h-3.5 w-3.5" />{{ d.view_count || 0 }}</span>
              <button
                v-if="canDeleteDiscussion(d.author_id)"
                class="text-xs font-bold text-[var(--color-danger-text)] transition hover:text-[var(--color-danger-text)]"
                @click.stop="deleteDiscussionById(d.id)"
              >
                 <span class="inline-flex items-center gap-1"><Icon icon="material-symbols:delete-outline" class="h-3.5 w-3.5" />删除</span>
              </button>
            </div>
          </div>
        </div>

        <!-- 空态 -->
        <div v-if="!isLoading && !error && filteredDiscussions.length === 0" class="ui-empty mt-6">
          <Icon icon="material-symbols:forum-outline" class="mb-2 h-12 w-12 text-slate-400" />
          <p class="font-bold text-[var(--color-foreground)]">暂无讨论</p>
          <p class="text-sm text-[var(--color-muted-foreground)]">发布第一个讨论吧</p>
        </div>
      </section>
    </div>

    <!-- ===== 讨论详情弹窗 ===== -->
    <Teleport to="body">
      <transition name="modal-fade">
        <div v-if="showDetail" class="disc-modal-overlay" @click.self="closeDetail">
          <div class="disc-modal">
            <div class="disc-modal-header">
              <h3 class="font-bold text-[var(--color-foreground)]">讨论详情</h3>
               <button class="disc-modal-close" aria-label="关闭" @click="closeDetail"><Icon icon="material-symbols:close" /></button>
            </div>
            <div class="disc-modal-body">
              <template v-if="currentDiscussion">
                <!-- 标题 -->
                <div class="mb-4">
                  <div class="flex items-center gap-2 mb-2">
                     <span v-if="currentDiscussion.is_pinned" class="ui-badge ui-badge-amber inline-flex items-center gap-1 text-[10px]"><Icon icon="material-symbols:push-pin" class="h-3 w-3" />置顶</span>
                    <span class="ui-badge ui-badge-blue text-[10px]">{{ currentDiscussion.category }}</span>
                  </div>
                  <h2 class="text-xl font-bold text-[var(--color-foreground)]">{{ currentDiscussion.title }}</h2>
                  <p class="mt-1 text-xs text-[var(--color-muted-foreground)]">{{ currentDiscussion.author_name }} · {{ formatFullTime(currentDiscussion.created_at) }}</p>
                </div>

                <!-- 标签 -->
                <div v-if="getTags(currentDiscussion.tags).length" class="mb-4 flex flex-wrap gap-1.5">
                  <span v-for="tag in getTags(currentDiscussion.tags)" :key="tag" class="rounded-md px-2 py-0.5 text-[11px] font-medium" :class="tagColors[tag] || 'bg-slate-100 text-slate-600'">{{ tag }}</span>
                </div>

                <!-- 内容 -->
                <div class="disc-content prose-wrapper mb-4">
                  <MarkdownComponent :content="{ content: currentDiscussion.content }" :show-nav="false" :show-heading-links="false" />
                </div>

                <!-- 操作栏 -->
                <div class="flex items-center gap-4 border-t border-[var(--color-border)] pt-3 mb-4">
                  <button
                    class="flex items-center gap-1.5 text-sm font-bold transition"
                    :class="currentDiscussion.is_liked ? 'text-[var(--color-accent-text)]' : 'text-[var(--color-muted-foreground)] hover:text-[var(--color-accent-text)]'"
                    @click="toggleLike(currentDiscussion)"
                  >
                     <Icon :icon="currentDiscussion.is_liked ? 'material-symbols:favorite' : 'material-symbols:favorite-outline'" class="h-4 w-4" />
                    点赞 {{ currentDiscussion.like_count || 0 }}
                  </button>
                   <span class="inline-flex items-center gap-1 text-sm text-[var(--color-muted-foreground)]"><Icon icon="material-symbols:chat-bubble-outline" class="h-4 w-4" />回复 {{ currentDiscussion.reply_count || 0 }}</span>
                   <span class="inline-flex items-center gap-1 text-sm text-[var(--color-muted-foreground)]"><Icon icon="material-symbols:visibility" class="h-4 w-4" />浏览 {{ currentDiscussion.view_count || 0 }}</span>
                  <button
                    v-if="canDeleteDiscussion(currentDiscussion.author_id)"
                    class="ml-auto flex items-center gap-1 text-sm font-bold text-[var(--color-danger-text)] transition hover:text-[var(--color-danger-text)]"
                    @click="deleteDiscussionById(currentDiscussion.id)"
                  >
                     <span class="inline-flex items-center gap-1"><Icon icon="material-symbols:delete-outline" class="h-4 w-4" />删除讨论</span>
                  </button>
                </div>

                <!-- 回复列表 -->
                <div class="border-t border-[var(--color-border)] pt-4">
                  <h4 class="text-sm font-bold text-[var(--color-foreground)] mb-3">回复 ({{ currentDiscussion.replies?.length || 0 }})</h4>
                  <div v-if="detailLoading" class="space-y-3">
                    <div v-for="i in 3" :key="i" class="ui-skeleton h-16 w-full rounded-lg"></div>
                  </div>
                  <div v-else-if="currentDiscussion.replies && currentDiscussion.replies.length" class="space-y-3">
                    <div v-for="r in currentDiscussion.replies" :key="r.id" class="rounded-lg border border-[var(--color-border)] p-3">
                      <div class="flex items-center justify-between mb-2">
                        <span class="text-xs font-bold text-[var(--color-foreground)]">{{ r.author_name }}</span>
                        <span class="text-[11px] text-[var(--color-muted-foreground)]">{{ formatTime(r.created_at) }}</span>
                      </div>
                      <div class="text-sm text-[var(--color-foreground)]">
                        <MarkdownComponent :content="{ content: r.content }" :show-nav="false" :show-heading-links="false" />
                      </div>
                       <div class="mt-2 flex items-center gap-3">
                         <button
                           class="flex items-center gap-1 text-xs font-bold transition"
                           :class="r.is_liked ? 'text-[var(--color-accent-text)]' : 'text-[var(--color-muted-foreground)] hover:text-[var(--color-accent-text)]'"
                           @click="toggleReplyLike(r)"
                         >
                            <Icon :icon="r.is_liked ? 'material-symbols:favorite' : 'material-symbols:favorite-outline'" class="h-4 w-4" />
                           {{ r.like_count || 0 }}
                         </button>
                         <button
                           v-if="canDeleteDiscussion(r.author_id)"
                           class="ml-auto flex items-center gap-1 text-xs font-bold text-[var(--color-danger-text)] transition hover:text-[var(--color-danger-text)]"
                           @click="deleteReplyById(r)"
                         >
                            <span class="inline-flex items-center gap-1"><Icon icon="material-symbols:delete-outline" class="h-3.5 w-3.5" />删除</span>
                         </button>
                       </div>
                    </div>
                  </div>
                  <p v-else class="text-sm text-[var(--color-muted-foreground)] text-center py-4">暂无回复</p>
                </div>

                <!-- 发表回复 -->
                <div v-if="authStore.isAuthenticated" class="border-t border-[var(--color-border)] pt-4 mt-4">
                  <textarea
                    v-model="newReply"
                    class="w-full rounded-lg border border-[var(--color-border)] bg-[var(--color-surface)] dark:bg-[var(--color-background)] p-3 text-sm text-[var(--color-foreground)] outline-none transition focus:border-[var(--color-accent)] resize-none"
                    rows="3"
                    placeholder="写下你的回复..."
                  ></textarea>
                  <div class="mt-2 flex justify-end">
                    <button
                      class="ui-btn ui-btn-primary ui-btn-sm"
                      :disabled="submittingReply || !newReply.trim()"
                      @click="submitReply"
                    >
                      {{ submittingReply ? '发送中...' : '发表回复' }}
                    </button>
                  </div>
                </div>
                <p v-else class="text-center text-sm text-[var(--color-muted-foreground)] py-4 border-t border-[var(--color-border)] mt-4">
                  <button class="font-bold text-[var(--color-accent-text)]" @click="goLogin">登录</button> 后参与讨论
                </p>
              </template>
            </div>
          </div>
        </div>
      </transition>
    </Teleport>

    <!-- ===== 发布讨论弹窗 ===== -->
    <Teleport to="body">
      <transition name="modal-fade">
        <div v-if="showCreate" class="disc-modal-overlay" @click.self="showCreate = false">
          <div class="disc-modal">
            <div class="disc-modal-header">
              <h3 class="font-bold text-[var(--color-foreground)]">发布讨论</h3>
               <button class="disc-modal-close" aria-label="关闭" @click="showCreate = false"><Icon icon="material-symbols:close" /></button>
            </div>
            <div class="disc-modal-body">
              <div class="space-y-4">
                <div>
                  <label class="mb-1 block text-xs font-bold text-[var(--color-muted-foreground)]">标题</label>
                  <input v-model="createForm.title" class="ui-input" placeholder="请输入标题" />
                </div>
                <div>
                  <label class="mb-1 block text-xs font-bold text-[var(--color-muted-foreground)]">分类</label>
                  <div class="flex flex-wrap gap-2">
                    <button
                      v-for="cat in ['问答', '分享', '闲聊', '综合']"
                      :key="cat"
                      class="rounded-md border px-3 py-1 text-xs font-medium transition-colors"
                      :class="createForm.category === cat
                        ? 'border-[var(--color-accent)] bg-[var(--color-accent-soft)] text-[var(--color-accent-text)] dark:border-[var(--color-accent)] dark:bg-[var(--color-accent-soft)] dark:text-[var(--color-accent-text)]'
                        : 'border-[var(--color-border)] text-[var(--color-muted-foreground)] dark:border-[var(--color-border-strong)] dark:text-[var(--color-muted-foreground)]'"
                      @click="createForm.category = cat"
                    >{{ cat }}</button>
                  </div>
                </div>
                <div>
                  <label class="mb-1 block text-xs font-bold text-[var(--color-muted-foreground)]">标签（逗号分隔）</label>
                  <input v-model="createForm.tags" class="ui-input" placeholder="如：动态规划, 算法" />
                </div>
                <div>
                  <label class="mb-1 block text-xs font-bold text-[var(--color-muted-foreground)]">内容（支持 Markdown）</label>
                  <textarea
                    v-model="createForm.content"
                    class="ui-input min-h-[160px] resize-y"
                    placeholder="请输入内容..."
                  ></textarea>
                </div>
                <div class="flex justify-end gap-2">
                  <button class="ui-btn ui-btn-ghost ui-btn-sm" @click="showCreate = false">取消</button>
                  <button
                    class="ui-btn ui-btn-primary ui-btn-sm"
                    :disabled="submitting || !createForm.title.trim() || !createForm.content.trim()"
                    @click="submitCreate"
                  >
                    {{ submitting ? '发布中...' : '发布' }}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </transition>
    </Teleport>
  </div>
</template>

<style scoped>
@reference 'tailwindcss';

.cat-ico {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: var(--color-accent-text);
}
.dark .cat-ico {
  color: var(--color-accent-text);
}
.cat-ico :deep(svg) {
  width: 20px;
  height: 20px;
}

.disc-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 10000;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(4px);
}
.disc-modal {
  width: 94%;
  max-width: 680px;
  max-height: 85vh;
  border-radius: 12px;
  background: var(--color-surface);
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.2);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
html.dark .disc-modal { background: var(--color-surface-muted); }
.disc-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid var(--color-border);
  flex-shrink: 0;
}
html.dark .disc-modal-header { border-color: var(--color-border-strong); }
.disc-modal-close {
  width: 28px; height: 28px;
  display: grid; place-items: center;
  border: none; border-radius: 6px;
  background: transparent; color: var(--color-muted-foreground);
  cursor: pointer; font-size: 14px;
}
.disc-modal-close:hover { background: var(--color-muted); }
.disc-modal-body {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
}
.disc-content :deep(p) { margin: 0 0 12px; }
.disc-content :deep(pre) {
  background: var(--color-surface-muted);
  padding: 12px;
  border-radius: 8px;
  font-size: 13px;
  overflow-x: auto;
}
html.dark .disc-content :deep(pre) { background: var(--color-surface); color: var(--color-foreground); }

.modal-fade-enter-active, .modal-fade-leave-active { transition: opacity 0.2s ease; }
.modal-fade-enter-from, .modal-fade-leave-to { opacity: 0; }
</style>
