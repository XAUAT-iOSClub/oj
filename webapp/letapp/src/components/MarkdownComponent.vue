<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch, withDefaults } from 'vue';
import { Icon } from '@iconify/vue';
import { useRoute } from 'vue-router';
import MarkdownIt from 'markdown-it';
import markdownitFootnote from 'markdown-it-footnote';
import markdownitTaskList from 'markdown-it-task-lists';
import markdownitAttrs from 'markdown-it-attrs';
import mdExpandTabs from 'markdown-it-expand-tabs';
import mdSup from 'markdown-it-sup';
import mdMark from 'markdown-it-mark';
import markdownItAnchor from 'markdown-it-anchor';
import markdownItContainer from 'markdown-it-container';
import DOMPurify from 'dompurify';
import katex from 'katex';
import 'katex/dist/katex.min.css';
import Prism from 'prismjs';
import 'prismjs/components/prism-bash';
import 'prismjs/components/prism-c';
import 'prismjs/components/prism-cpp';
import 'prismjs/components/prism-css';
import 'prismjs/components/prism-go';
import 'prismjs/components/prism-java';
import 'prismjs/components/prism-javascript';
import 'prismjs/components/prism-json';
import 'prismjs/components/prism-markup';
import 'prismjs/components/prism-markup-templating';
import 'prismjs/components/prism-python';
import 'prismjs/components/prism-rust';
import 'prismjs/components/prism-typescript';
import 'prismjs/themes/prism-tomorrow.min.css';

interface Content {
  title?: string;
  date?: string;
  watch?: number;
  content: string;
}

interface HeadingItem {
  id: string;
  text: string;
  level: number;
  href: string;
  children: HeadingItem[];
}

/** 抛给父级的扁平标题大纲，用于把目录渲染到组件外（例如学习页的侧栏）。 */
interface HeadingOutline {
  id: string;
  text: string;
  level: number;
}

const props = withDefaults(defineProps<{
  content?: Content;
  source?: string;
  showNav?: boolean;
  showHeadingLinks?: boolean;
  baseDir?: string;
}>(), {
  showNav: true,
  showHeadingLinks: true,
  baseDir: '',
});

const emit = defineEmits<{
  (e: 'navigate', file: string): void;
  (e: 'headings', headings: HeadingOutline[]): void;
  (e: 'active-heading', id: string): void;
}>();

const route = useRoute();
const headings = ref<HeadingItem[]>([]);
const html = ref('');
const readingProgress = ref(0);
const activeHeadingId = ref('');
const markdownBody = ref<HTMLElement | null>(null);
const copiedIndex = ref<number | null>(null);

const normalizeLanguage = (language: string) => {
  const aliases: Record<string, string> = {
    js: 'javascript',
    ts: 'typescript',
    py: 'python',
    sh: 'bash',
    shell: 'bash',
    cplusplus: 'cpp',
    html: 'markup',
    xml: 'markup',
    svg: 'markup',
    vue: 'markup',
    svelte: 'markup',
    template: 'markup',
    jsx: 'javascript',
    mjs: 'javascript',
    cjs: 'javascript',
    script: 'javascript',
  };

  const key = language.trim().toLowerCase().replace(/[^a-z0-9_-]/g, '');
  return aliases[key] || key;
};

const highlightSafe = (code: string, language: string, fallback: string = 'javascript'): string => {
  const grammar = Prism.languages[language] || Prism.languages[fallback];
  if (!grammar) return escapeHtml(code);
  return Prism.highlight(code, grammar, language);
};

const escapeHtml = (value: string) => value
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;');

const md = new MarkdownIt({
  html: true,
  linkify: true,
  typographer: false,
  highlight: (code: string, language: string): string => {
    const lang = (language || '').trim().toLowerCase();
    let targetLang = normalizeLanguage(lang);
    if (!targetLang) {
      if (code.includes('<script') || code.includes('<template') || code.includes('<style')) {
        targetLang = 'markup';
      } else {
        targetLang = 'javascript';
      }
    }

    const highlighted = highlightSafe(code, targetLang);
    const escapedCode = escapeHtml(code);
    return `<div class="code-block-wrapper" data-lang="${targetLang}"><div class="code-block-header"><span class="code-lang-label">${targetLang}</span><button class="code-copy-btn" data-code="${escapedCode}"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg> 复制</button></div><pre class="language-${targetLang}"><code class="language-${targetLang}">${highlighted}</code></pre></div>`;
  },
});

// 用户原始 HTML 不能带样式覆盖页面；KaTeX 生成的布局样式在最终净化时保留。
for (const rule of ['html_block', 'html_inline']) {
  md.renderer.rules[rule] = (tokens, index) => DOMPurify.sanitize(tokens[index]?.content || '', {
    FORBID_TAGS: ['style', 'form', 'iframe', 'object', 'embed'], FORBID_ATTR: ['style', 'srcdoc'],
  });
}

md.use(markdownItAnchor, {
  permalink: markdownItAnchor.permalink.ariaHidden({
    placement: 'before',
    space: true,
    class: 'heading-anchor',
    renderHref: (href: string) => `${route.path}#${href}`,
  }),
});
md.use(markdownitFootnote);
md.use(markdownitTaskList, { label: false, labelAfter: false });
md.use(markdownitAttrs, {
  allowedAttributes: ['id', 'class', 'target', 'src', 'alt', 'title'],
});
md.use(mdExpandTabs)
  .use(mdSup)
  .use(mdMark);
const defaultFence = md.renderer.rules.fence!;
md.renderer.rules.fence = (tokens, idx, options, env, self) => {
  if (tokens[idx]?.info.trim() === 'mermaid') return `<pre class="mermaid">${escapeHtml(tokens[idx]!.content)}</pre>`;
  const token = tokens[idx];
  if (token && options.highlight) return options.highlight(token.content, token.info, '') || defaultFence(tokens, idx, options, env, self);
  return defaultFence(tokens, idx, options, env, self);
};

// 公式渲染：行内 $...$ 与块级 $$...$$ 交由 KaTeX 处理
const renderKatex = (md: any): void => {
  // 块级公式 $$...$$
  md.block.ruler.before('fence', 'katex_block', (state: any, startLine: number, endLine: number, silent: boolean) => {
    const startPos = state.bMarks[startLine] + state.tShift[startLine];
    const maxPos = state.eMarks[startLine];
    if (startPos + 1 >= maxPos) return false;
    if (state.src.slice(startPos, startPos + 2) !== '$$') return false;

    let content = '';
    let found = false;
    let lastLine = startLine;
    const firstLine = state.src.slice(startPos + 2, maxPos);
    if (firstLine.trim().endsWith('$$')) {
      content = firstLine.trim().slice(0, -2).trim();
      found = true;
    } else {
      content = firstLine;
      for (let line = startLine + 1; line < endLine; line++) {
        const ls = state.bMarks[line] + state.tShift[line];
        const le = state.eMarks[line];
        const text = state.src.slice(ls, le);
        if (text.trim().endsWith('$$')) {
          content += '\n' + text.trim().slice(0, -2);
          lastLine = line;
          found = true;
          break;
        }
        content += '\n' + text;
        lastLine = line;
      }
    }
    if (!found) return false;
    if (!silent) {
      const token = state.push('katex_block', 'math', 0);
      token.block = true;
      token.content = content.trim();
      token.map = [startLine, lastLine + 1];
    }
    state.line = lastLine + 1;
    return true;
  });

  md.renderer.rules['katex_block'] = (tokens: any, idx: number) =>
    safeKatex(tokens[idx].content, true);

  // 行内公式 $...$（\$ 转义不参与解析；$$ 交给块级规则）
  md.inline.ruler.before('escape', 'katex_inline', (state: any, silent: boolean) => {
    const start = state.pos;
    if (state.src[start] !== '$') return false;
    if (start > 0 && state.src[start - 1] === '\\') return false;
    if (state.src[start + 1] === '$') return false;
    const end = state.src.indexOf('$', start + 1);
    if (end === -1 || end === start + 1) return false;
    const content = state.src.slice(start + 1, end);
    if (!content.trim()) return false;
    if (!silent) {
      const token = state.push('katex_inline', 'math', 0);
      token.content = content;
    }
    state.pos = end + 1;
    return true;
  });

  md.renderer.rules['katex_inline'] = (tokens: any, idx: number) =>
    safeKatex(tokens[idx].content, false);
};

const safeKatex = (content: string, displayMode: boolean): string => {
  try {
    return katex.renderToString(content, {
      displayMode,
      throwOnError: false,
      errorColor: '#DC2626',
    });
  } catch {
    return `<span class="katex-error">${escapeHtml(content)}</span>`;
  }
};

md.use(renderKatex);

const resolveMdLink = (href: string, baseDir: string): string | null => {
  if (!href || href.startsWith('#') || href.startsWith('http://') || href.startsWith('https://') || href.startsWith('mailto:') || href.startsWith('javascript:')) {
    return null;
  }
  const cleanHref = (href.split('?')[0] || '').split('#')[0] || '';
  if (!cleanHref.endsWith('.md')) {
    return null;
  }
  const resolved = cleanHref.startsWith('/')
    ? cleanHref.replace(/^\//, '')
    : `${baseDir}${baseDir && !baseDir.endsWith('/') ? '/' : ''}${cleanHref}`;
  return resolved;
};

md.core.ruler.push('resolve_md_links', (state) => {
  const baseDir = (state.env as any)?.baseDir || '';
  if (!baseDir) return;
  const tokens = state.tokens;
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (!token || token.type !== 'inline') continue;
    const inlineTokens = token.children || [];
    for (let j = 0; j < inlineTokens.length; j++) {
      const inlineToken = inlineTokens[j];
      if (!inlineToken || inlineToken.type !== 'link_open') continue;
      const hrefAttr = inlineToken.attrGet('href');
      if (!hrefAttr) continue;
      const resolved = resolveMdLink(hrefAttr, baseDir);
      if (resolved) {
        inlineToken.attrSet('data-md-link', resolved);
      }
    }
  }
});

/** 重写图片路径：将相对路径转为同源静态资源 URL */
md.core.ruler.push('resolve_images', (state) => {
  const baseDir = (state.env as any)?.baseDir || '';
  const tokens = state.tokens;
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (!token || token.type !== 'inline') continue;
    const inlineTokens = token.children || [];
    for (let j = 0; j < inlineTokens.length; j++) {
      const inlineToken = inlineTokens[j];
      if (!inlineToken || inlineToken.type !== 'image') continue;
      const src = inlineToken.attrGet('src');
      if (!src) continue;
      // 跳过已经是绝对 URL 的图片
      if (src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:')) continue;
      // 解析相对路径
      const cleanSrc = (src.split('?')[0] || '').split('#')[0] || '';
      let resolvedPath: string;
      if (cleanSrc.startsWith('/')) {
        resolvedPath = cleanSrc.replace(/^\//, '');
      } else if (baseDir) {
        resolvedPath = `${baseDir}/${cleanSrc}`;
      } else {
        resolvedPath = cleanSrc || '';
      }
      // 规范化路径（处理 ../）
      const parts = resolvedPath.split('/');
      const normalized: string[] = [];
      for (const p of parts) {
        if (p === '..') { normalized.pop(); }
        else if (p !== '.' && p !== '') { normalized.push(p); }
      }
      const finalPath = normalized.join('/');
      // 设置为同源静态资源 URL（学习资料由前端 public/learn 托管）
      inlineToken.attrSet('src', `/learn-dist/${finalPath}`);
    }
  }
});

[
  { name: 'tip', className: 'tip' },
  { name: 'note', className: 'note' },
  { name: 'warning', className: 'warning' },
  { name: 'danger', className: 'danger' },
  { name: 'example', className: 'example' },
  { name: 'success', className: 'success' },
].forEach(({ name, className }) => {
  md.use(markdownItContainer, name, {
    validate: (params: string) => Boolean(params.trim().match(new RegExp(`^${name}\\s+(.*)$`))),
    render: (tokens: any[], idx: number) => {
      const match = tokens[idx].info.trim().match(new RegExp(`^${name}\\s+(.*)$`));
      if (tokens[idx].nesting === 1) {
        return `<div class="${className} custom-block"><p class="custom-block-title">${md.utils.escapeHtml(match?.[1] || '')}</p>\n`;
      }

      return '</div>\n';
    },
  });
});

// \u5fc5\u987b\u4e0e markdown-it-anchor \u7684\u9ed8\u8ba4 slugify \u4fdd\u6301\u4e00\u81f4\uff0c\u5426\u5219\u76ee\u5f55\u62ff\u5230\u7684 id \u4e0e\u6807\u9898\u5b9e\u9645
// \u5199\u5165 DOM \u7684 id \u4e0d\u540c\uff0c\u951a\u70b9\u8df3\u8f6c\u548c\u5f53\u524d\u5c0f\u8282\u9ad8\u4eae\u90fd\u4f1a\u5931\u6548\u3002
const slugifyHeading = (text: string) =>
  encodeURIComponent(text.trim().toLowerCase().replace(/\s+/g, '-'));

const extractHeadings = (tokens: ReturnType<typeof md.parse>) => {
  const extractedHeadings: HeadingItem[] = [];
  // markdown-it-anchor \u4f1a\u7ed9\u91cd\u590d\u6807\u9898\u4f9d\u6b21\u8ffd\u52a0 -1\u3001-2\uff0c\u8fd9\u91cc\u590d\u73b0\u540c\u6837\u7684\u53bb\u91cd\u89c4\u5219\u3002
  const usedSlugs = new Set<string>();

  for (let i = 0; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token?.type !== 'heading_open') {
      continue;
    }

    const level = Number.parseInt(token.tag.slice(1), 10);
    const nextToken = tokens[i + 1];

    if (nextToken?.type === 'inline') {
      // \u4e0e markdown-it-anchor \u7684 getTokensText \u4e00\u81f4\uff1a\u53ea\u53d6\u6587\u672c\u4e0e\u884c\u5185\u4ee3\u7801\u3002
      // permalinkSpace \u4f1a\u5f80 children \u91cc\u585e\u4e00\u4e2a " "\uff0c\u5fc5\u987b trim \u6389\u518d\u4f5c\u4e3a\u6807\u9898\u6587\u672c\u3002
      const text = (nextToken.children || [])
        .filter((child) => child.type === 'text' || child.type === 'code_inline')
        .map((child) => child.content)
        .join('')
        .trim();
      const base = slugifyHeading(text);
      let id = base;
      let suffix = 1;
      while (usedSlugs.has(id)) {
        id = `${base}-${suffix}`;
        suffix += 1;
      }
      usedSlugs.add(id);

      extractedHeadings.push({
        id,
        text,
        level,
        href: `#${id}`,
        children: [],
      });
    }
  }

  return extractedHeadings;
};

const buildHeadingTree = (flatHeadings: HeadingItem[]) => {
  const tree: HeadingItem[] = [];
  const stack: HeadingItem[] = [];

  flatHeadings.forEach((heading) => {
    const item = { ...heading, children: [] };

    while (stack.length > 0) {
      const lastItem = stack[stack.length - 1];
      if (!lastItem || lastItem.level < heading.level) {
        break;
      }

      stack.pop();
    }

    if (stack.length === 0) {
      tree.push(item);
    } else {
      const parent = stack[stack.length - 1];
      if (parent) {
        parent.children.push(item);
      } else {
        tree.push(item);
      }
    }

    stack.push(item);
  });

  return tree;
};

/** 按阅读顺序摊平标题树，父级在前、子级紧随其后。 */
function flattenHeadings(nodes: HeadingItem[]): HeadingOutline[] {
  return nodes.flatMap((node) => [
    { id: node.id, text: node.text, level: node.level },
    ...flattenHeadings(node.children),
  ]);
}

const render = async (markdown: string) => {
  const env = { baseDir: props.baseDir };
  const tokens = md.parse(markdown, env);
  const tree = buildHeadingTree(extractHeadings(tokens));
  headings.value = tree;
  // 换文档时先清掉上一份的当前小节，避免滚动前残留高亮。
  activeHeadingId.value = '';
  // immediate 时本函数仍在 setup 期间执行，推迟一拍再通知父级，避免父级在渲染中被改写。
  void nextTick(() => emit('headings', flattenHeadings(tree)));
  const renderedHtml = md.renderer.render(tokens, md.options, env);
  const finalHtml = props.showHeadingLinks
    ? renderedHtml
    : renderedHtml.replace(/<a\b[^>]*class="[^"]*heading-anchor[^"]*"[^>]*>[\s\S]*?<\/a>/g, '');
  return DOMPurify.sanitize(finalHtml, { FORBID_TAGS: ['style', 'iframe', 'object', 'embed', 'form'],
    FORBID_ATTR: ['srcdoc'], ADD_ATTR: ['target'], ALLOW_DATA_ATTR: true });
};

const processCodeBlocks = () => {
  if (!markdownBody.value) return;
  const blocks = markdownBody.value.querySelectorAll('.code-block-wrapper');
  blocks.forEach((block) => {
    const btn = block.querySelector('.code-copy-btn');
    if (btn && !btn.getAttribute('data-bound')) {
      btn.setAttribute('data-bound', 'true');
    }
  });
  // 宽内容容器：表格统一包一层横向滚动容器，避免页面级横向溢出
  markdownBody.value.querySelectorAll('table').forEach((table) => {
    const parent = table.parentElement;
    if (parent && parent.classList.contains('table-wrapper')) return;
    const wrap = document.createElement('div');
    wrap.className = 'table-wrapper';
    if (table.parentNode) table.parentNode.insertBefore(wrap, table);
    wrap.appendChild(table);
  });
};

const copyCode = async (code: string, index?: number) => {
  try {
    await navigator.clipboard.writeText(code);
    if (typeof index === 'number') {
      copiedIndex.value = index;
      setTimeout(() => { copiedIndex.value = null; }, 2000);
    }
  } catch {
    const textarea = document.createElement('textarea');
    textarea.value = code;
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
    if (typeof index === 'number') {
      copiedIndex.value = index;
      setTimeout(() => { copiedIndex.value = null; }, 2000);
    }
  }
};

let renderVersion = 0;
watch(
  () => [props.content, props.source, props.showHeadingLinks, props.baseDir] as const,
  async ([content, source]) => {
    const version = ++renderVersion;
    const sourceText = content?.content || source || '';
    html.value = sourceText ? await render(sourceText) : '';
    await nextTick();
    if (version !== renderVersion) return;
    processCodeBlocks(); // Prism 已在 Markdown 渲染时高亮，不再重复遍历整个页面。
    const nodes = markdownBody.value?.querySelectorAll<HTMLElement>('.mermaid');
    if (nodes?.length) {
      try {
        const { default: mermaid } = await import('mermaid');
        if (version !== renderVersion) return;
        mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', maxTextSize: 50000 });
        await mermaid.run({ nodes: Array.from(nodes) });
      } catch { /* 保留转义的图表源代码作为可读回退。 */ }
    }
  },
  { immediate: true },
);

// 当前小节由窗口滚动驱动，这里只把它转告给父级（例如学习页的侧栏目录）。
watch(activeHeadingId, (id) => emit('active-heading', id));

const anchorLinks = computed(() => headings.value);
import { formatDate } from '../utils/time';
const date = computed(() => (props.content?.date ? formatDate(props.content?.date) : ''));
const hasHeaderMeta = computed(() => Boolean(props.content?.title || props.content?.date || props.content?.watch));

const handleAnchorClick = (event: Event, href: string) => {
  event.preventDefault();
  // id 经过 encodeURIComponent，含 % 无法直接拼进 CSS 选择器，只能按 id 查找。
  const targetElement = document.getElementById(href.replace(/^#/, ''));

  if (targetElement) {
    targetElement.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
};

let scrollTicking = false;

const handleMarkdownClick = (event: Event) => {
  const target = event.target as HTMLElement;
  const button = target.closest<HTMLElement>('.code-copy-btn');
  if (button) { handleCopyButton(button); return; }
  const anchor = target.closest('a');
  if (!anchor) return;
  const mdLink = anchor.getAttribute('data-md-link');
  if (mdLink) {
    event.preventDefault();
    emit('navigate', mdLink);
  }
};

const handleScroll = () => {
  if (scrollTicking) return;
  scrollTicking = true;

  requestAnimationFrame(() => {
    const scrollTop = window.scrollY;
    const docHeight = document.documentElement.scrollHeight - window.innerHeight;
    readingProgress.value = docHeight > 0 ? Math.min((scrollTop / docHeight) * 100, 100) : 0;

    const articleHeadings = markdownBody.value?.querySelectorAll('h1, h2, h3, h4, h5, h6') || [];
    let foundId = '';

    for (let i = articleHeadings.length - 1; i >= 0; i -= 1) {
      const heading = articleHeadings[i];
      if (heading && heading.getBoundingClientRect().top <= 120) {
        foundId = heading.id;
        break;
      }
    }

    activeHeadingId.value = foundId;
    scrollTicking = false;
  });
};

const handleCopyButton = (btn: HTMLElement) => {
    const code = btn.getAttribute('data-code') || '';
    copyCode(code);
    const originalHTML = btn.innerHTML;
    btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg> 已复制';
    btn.classList.add('copied');
    setTimeout(() => {
      btn.innerHTML = originalHTML;
      btn.classList.remove('copied');
    }, 2000);
  };

onMounted(() => {
  window.addEventListener('scroll', handleScroll, { passive: true });
  if (markdownBody.value) {
    markdownBody.value.addEventListener('click', handleMarkdownClick);
  }
});

onUnmounted(() => {
  window.removeEventListener('scroll', handleScroll);
  renderVersion += 1;
  if (markdownBody.value) {
    markdownBody.value.removeEventListener('click', handleMarkdownClick);
  }
});
</script>

<template>
  <div v-if="content || source" class="learn-reader-layout">
    <!-- 阅读进度条 -->
    <div class="reading-progress-track">
      <div class="reading-progress-bar" :style="{ width: readingProgress + '%' }"></div>
    </div>

    <!-- 正文区域 -->
    <div class="learn-reader-main" :class="[showNav && headings.length > 0 ? 'has-toc' : 'no-toc']">
      <article class="markdown-article">
        <header v-if="hasHeaderMeta" class="article-header">
          <h1 class="article-title">
            {{ content?.title }}
          </h1>
          <div class="article-meta">
            <time v-if="date" class="meta-item">
              <Icon icon="mdi:calendar" width="15" height="15" />
              {{ date }}
            </time>
            <span v-if="content?.watch" class="meta-item">
              <Icon icon="mdi:eye" width="15" height="15" />
              {{ content.watch }}
            </span>
          </div>
        </header>

        <div ref="markdownBody" class="markdown-content" v-html="html"></div>
      </article>
    </div>

    <!-- 右侧目录 -->
    <aside v-if="showNav && headings.length > 0" class="learn-reader-toc">
      <nav class="toc-nav">
        <h3 class="toc-title">目录</h3>
        <ul class="toc-list">
          <li v-for="link in anchorLinks" :key="link.href" class="toc-item">
            <a
              :href="link.href"
              class="toc-link"
              :class="{ active: activeHeadingId === link.id }"
              @click="handleAnchorClick($event, link.href)"
            >
              <span class="toc-indicator"></span>
              {{ link.text }}
            </a>
            <ul v-if="link.children.length > 0" class="toc-sublist">
              <li v-for="subLink in link.children" :key="subLink.href" class="toc-subitem">
                <a
                  :href="subLink.href"
                  class="toc-sublink"
                  :class="{ active: activeHeadingId === subLink.id }"
                  @click="handleAnchorClick($event, subLink.href)"
                >
                  {{ subLink.text }}
                </a>
              </li>
            </ul>
          </li>
        </ul>
      </nav>
    </aside>
  </div>

  <div v-else class="flex h-full flex-col items-center justify-center p-8 text-center">
    <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-md border-2 border-dashed border-slate-300 bg-slate-100 dark:border-slate-700 dark:bg-slate-900">
      <Icon icon="mdi:file-document-outline" width="32" height="32" class="text-slate-500 dark:text-slate-400" />
    </div>
    <p class="text-lg text-slate-500 dark:text-slate-400">请选择一篇资料开始阅读</p>
  </div>
</template>

<style scoped>
@reference 'tailwindcss';

/* ===== 阅读器双栏布局 ===== */
.learn-reader-layout {
  display: flex;
  gap: 36px;
  max-width: 1320px;
  margin: 0 auto;
  position: relative;
}

.learn-reader-main {
  flex: 1;
  min-width: 0;
  max-width: 900px;
  padding: 0 8px;
}

.learn-reader-main.has-toc {
  flex: 0 0 72%;
  max-width: 72%;
}

.learn-reader-main.no-toc {
  max-width: 1080px;
  margin: 0 auto;
}

/* ===== 阅读进度条 ===== */
.reading-progress-track {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  height: 3px;
  background: transparent;
  z-index: 100;
}

.reading-progress-bar {
  height: 100%;
  background: var(--color-accent);
  border-radius: 0 2px 2px 0;
  transition: width 0.1s ease-out;
}

/* ===== 右侧目录 ===== */
.learn-reader-toc {
  flex: 0 0 250px;
  width: 250px;
  align-self: flex-start;
  position: sticky;
  top: 88px;
  max-height: calc(100vh - 112px);
  overflow-y: auto;
  scrollbar-width: none;
}

.learn-reader-toc::-webkit-scrollbar {
  display: none;
}

.toc-nav {
  padding: 20px 20px 24px;
  border-radius: 12px;
  border: 1px solid var(--color-border);
  background: var(--color-surface);
}

:global(html.dark) .toc-nav {
  border-color: var(--color-border);
  background: var(--color-surface);
}

.toc-title {
  font-size: 15px;
  font-weight: 650;
  color: var(--color-foreground);
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--color-border);
}

:global(html.dark) .toc-title {
  color: var(--color-foreground);
  border-color: var(--color-border);
}

.toc-list {
  list-style: none;
  padding: 0;
  margin: 0;
}

.toc-item {
  margin-bottom: 2px;
}

.toc-link {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  border-radius: 6px;
  font-size: 14px;
  font-weight: 500;
  color: var(--color-muted-foreground);
  text-decoration: none;
  transition: all 0.15s;
  line-height: 1.5;
}

.toc-link:hover {
  background: var(--color-surface-muted);
  color: var(--color-accent-text);
}

:global(html.dark) .toc-link {
  color: var(--color-muted-foreground);
}

:global(html.dark) .toc-link:hover {
  background: var(--color-surface-muted);
  color: var(--color-accent-text);
}

.toc-indicator {
  display: none;
  width: 2px;
  height: 16px;
  border-radius: 1px;
  background: var(--color-accent-solid);
  flex-shrink: 0;
}

.toc-link.active {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
  font-weight: 600;
}

.toc-link.active .toc-indicator {
  display: block;
}

:global(html.dark) .toc-link.active {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
}

.toc-sublist {
  list-style: none;
  padding: 0;
  margin: 2px 0 2px 20px;
}

.toc-subitem {
  margin-bottom: 1px;
}

.toc-sublink {
  display: block;
  padding: 4px 10px;
  border-radius: 5px;
  font-size: 13px;
  color: var(--color-muted-foreground);
  text-decoration: none;
  transition: all 0.15s;
  line-height: 1.5;
}

.toc-sublink:hover {
  background: var(--color-surface-muted);
  color: var(--color-accent-text);
}

.toc-sublink.active {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
  font-weight: 600;
}

:global(html.dark) .toc-sublink {
  color: var(--color-muted-foreground);
}

:global(html.dark) .toc-sublink:hover {
  background: var(--color-surface-muted);
  color: var(--color-accent-text);
}

:global(html.dark) .toc-sublink.active {
  background: var(--color-accent-soft);
  color: var(--color-accent-text);
}

/* ===== 文章头部 ===== */
.article-header {
  margin-bottom: 36px;
  padding-bottom: 28px;
  border-bottom: 1px solid var(--color-border);
}

:global(html.dark) .article-header {
  border-color: var(--color-border);
}

.article-title {
  font-size: 34px;
  font-weight: 700;
  line-height: 1.3;
  color: var(--color-foreground);
  letter-spacing: -0.02em;
}

:global(html.dark) .article-title {
  color: var(--color-foreground);
}

.article-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 16px;
  margin-top: 16px;
}

.meta-item {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 13px;
  color: var(--color-muted-foreground);
}

/* ===== 设计令牌（统一 Markdown 内容组件体系） ===== */
.markdown-content {
  /* 间距体系：正文 < 标题与正文 < 独立块与正文 */
  --md-space-sm: 16px;   /* 段落之间 */
  --md-space-md: 20px;   /* 标题与正文 / 折叠块 */
  --md-space-lg: 28px;   /* 代码/公式/表格/图片/引用/提示 与正文 */
  /* 圆角 */
  --md-radius-sm: 5px;
  --md-radius-md: 8px;
  --md-radius-lg: 10px;
  /* 边框与背景（亮色） */
  --md-border: var(--color-border);
  --md-border-soft: var(--color-border);
  --md-tint: var(--color-surface-muted);
  --md-tint-2: #F1F5F9;
  /* 文本 */
  --md-text: var(--color-foreground);
  --md-text-strong: var(--color-foreground);
  --md-text-muted: var(--color-muted-foreground);
  --md-accent: var(--color-accent);
}
:global(html.dark) .markdown-content {
  --md-border: var(--color-border-strong);
  --md-border-soft: var(--color-border);
  --md-tint: var(--color-background);
  --md-tint-2: #1E293B;
  --md-text: var(--color-foreground);
  --md-text-strong: var(--color-foreground);
  --md-text-muted: var(--color-muted-foreground);
  --md-accent: var(--color-accent);
}

/* ===== 正文 Markdown 内容 ===== */
.markdown-content :deep(h1) {
  font-size: 28px;
  font-weight: 700;
  margin-top: 52px;
  margin-bottom: 18px;
  color: var(--color-foreground);
  line-height: 1.35;
  letter-spacing: -0.01em;
}

.markdown-content :deep(h2) {
  font-size: 22px;
  font-weight: 650;
  margin-top: 40px;
  margin-bottom: 14px;
  color: var(--color-foreground);
  line-height: 1.4;
}

/* 正文首行的标题就是文档标题，上方已有页面工具条，不需要再加一段间距。 */
.markdown-content :deep(> h1:first-child),
.markdown-content :deep(h1:first-child) {
  margin-top: 0;
  letter-spacing: -0.02em;
}

.markdown-content :deep(h3) {
  font-size: 18px;
  font-weight: 600;
  margin-top: 32px;
  margin-bottom: 12px;
  color: var(--color-foreground);
  line-height: 1.45;
}

.markdown-content :deep(h4) {
  font-size: 16px;
  font-weight: 600;
  margin-top: 28px;
  margin-bottom: 10px;
  color: var(--color-foreground);
}

:global(html.dark) .markdown-content :deep(h1),
:global(html.dark) .markdown-content :deep(h2),
:global(html.dark) .markdown-content :deep(h3),
:global(html.dark) .markdown-content :deep(h4) {
  color: var(--color-foreground);
}

.markdown-content :deep(p) {
  font-size: 15.5px;
  line-height: 1.85;
  color: var(--color-foreground);
  margin-bottom: 16px;
}

:global(html.dark) .markdown-content :deep(p) {
  color: var(--color-foreground);
}

.markdown-content :deep(strong) {
  font-weight: 600;
  color: var(--color-foreground);
}

:global(html.dark) .markdown-content :deep(strong) {
  color: var(--color-foreground);
}

.markdown-content :deep(a) {
  color: var(--color-accent-text);
  text-decoration: none;
  border-bottom: 1px solid transparent;
  transition: border-color 0.15s;
  /* 正文里常有整条 URL，窄屏必须允许在任意位置断行，否则会撑出横向滚动。 */
  overflow-wrap: anywhere;
}

.markdown-content :deep(a:hover) {
  border-bottom-color: var(--color-accent);
}

:global(html.dark) .markdown-content :deep(a) {
  color: var(--color-accent-text);
}

:global(html.dark) .markdown-content :deep(a:hover) {
  border-bottom-color: var(--color-accent);
}

/* ===== 标题锚点链接 ===== */
.markdown-content :deep(.heading-anchor) {
  display: inline-flex;
  align-items: center;
  margin-left: 6px;
  color: var(--color-foreground);
  font-size: 0.8em;
  opacity: 0;
  transition: opacity 0.15s;
  text-decoration: none;
  border: none;
}

.markdown-content :deep(h1:hover .heading-anchor),
.markdown-content :deep(h2:hover .heading-anchor),
.markdown-content :deep(h3:hover .heading-anchor),
.markdown-content :deep(h4:hover .heading-anchor) {
  opacity: 1;
}

:global(html.dark) .markdown-content :deep(.heading-anchor) {
  color: var(--color-muted-foreground);
}

/* ===== 列表 ===== */
.markdown-content :deep(ul),
.markdown-content :deep(ol) {
  padding-left: 24px;
  margin-bottom: 16px;
}

.markdown-content :deep(li) {
  font-size: 15.5px;
  line-height: 1.85;
  color: var(--color-foreground);
  padding: 3px 0;
}

:global(html.dark) .markdown-content :deep(li) {
  color: var(--color-foreground);
}

.markdown-content :deep(ul li) {
  list-style-type: disc;
}

.markdown-content :deep(ol li) {
  list-style-type: decimal;
}

.markdown-content :deep(ul ul li) {
  list-style-type: circle;
}

.markdown-content :deep(ol ol li),
.markdown-content :deep(ul ol li) {
  list-style-type: lower-alpha;
}

/* ===== 引用块（轻强调：左侧强调线 + 轻背景） ===== */
.markdown-content :deep(blockquote) {
  margin: var(--md-space-lg) 0;
  padding: 16px 20px;
  border-left: 3px solid var(--md-accent);
  background: var(--md-tint);
  border-radius: 0 var(--md-radius-md) var(--md-radius-md) 0;
  color: var(--md-text-muted);
}
.markdown-content :deep(blockquote p) {
  margin-bottom: 8px;
}
.markdown-content :deep(blockquote p:last-child) {
  margin-bottom: 0;
}
/* 多级引用：限制视觉层级，超过两层使用更深一级背景而非无限缩进 */
.markdown-content :deep(blockquote blockquote) {
  background: var(--md-tint-2);
}

/* ===== 代码块（强独立内容：轻边框容器） ===== */
.markdown-content :deep(.code-block-wrapper) {
  margin: var(--md-space-lg) 0;
  border-radius: var(--md-radius-md);
  overflow: hidden;
  border: 1px solid var(--md-border);
  background: var(--md-tint);
  box-shadow: none;
}
.markdown-content :deep(.code-block-header) {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 7px 14px;
  background: var(--md-tint-2);
  border-bottom: 1px solid var(--md-border);
}
.markdown-content :deep(.code-lang-label) {
  font-size: 12px;
  font-weight: 600;
  color: var(--md-text-muted);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.markdown-content :deep(.code-copy-btn) {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 10px;
  border-radius: 6px;
  border: none;
  background: transparent;
  font-size: 12px;
  font-weight: 600;
  color: var(--md-text-muted);
  cursor: pointer;
  transition: all 0.15s;
  font-family: inherit;
}
.markdown-content :deep(.code-copy-btn:hover) {
  background: var(--md-border);
  color: var(--md-text-strong);
}
.markdown-content :deep(.code-copy-btn.copied) {
  color: var(--color-signal-text);
}
.markdown-content :deep(pre) {
  margin: 0;
  padding: 18px 24px;
  font-size: 13.5px;
  line-height: 1.7;
  border-radius: 0;
  border: none;
  background: transparent;
  overflow-x: auto;
  white-space: pre;
  scrollbar-width: thin;
}
.markdown-content :deep(pre code) {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 13.5px;
  white-space: pre;
}

/* ===== 行内代码（融入正文，不做成按钮） ===== */
.markdown-content :deep(code):not(pre code):not(.code-block-wrapper code) {
  background: var(--md-tint-2);
  color: var(--md-accent);
  padding: 2px 6px;
  border-radius: var(--md-radius-sm);
  font-size: 0.9em;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-weight: 500;
  word-break: break-word;
}

/* ===== 表格（强独立内容：轻边框容器 + 横向滚动 + 表头吸顶） ===== */
.markdown-content :deep(.table-wrapper) {
  margin: var(--md-space-lg) 0;
  border: 1px solid var(--md-border);
  border-radius: var(--md-radius-lg);
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: thin;
}
.markdown-content :deep(table) {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
}
.markdown-content :deep(th) {
  position: sticky;
  top: 0;
  background: var(--md-tint-2);
  padding: 12px 16px;
  font-size: 13px;
  font-weight: 700;
  color: var(--md-text-muted);
  text-align: left;
  border-bottom: 1px solid var(--md-border);
  z-index: 1;
}
.markdown-content :deep(td) {
  padding: 12px 16px;
  font-size: 14px;
  color: var(--md-text);
  border-bottom: 1px solid var(--md-border-soft);
}
.markdown-content :deep(tr:last-child td) {
  border-bottom: none;
}
.markdown-content :deep(tr:hover td) {
  background: var(--md-tint);
}

/* ===== 图片（强独立内容） ===== */
.markdown-content :deep(img) {
  display: block;
  max-width: 100%;
  height: auto;
  margin: var(--md-space-lg) auto;
  border-radius: var(--md-radius-md);
  border: 1px solid var(--md-border-soft);
}
.markdown-content :deep(figure) {
  margin: var(--md-space-lg) 0;
}
.markdown-content :deep(figcaption) {
  margin-top: 10px;
  font-size: 13px;
  color: var(--md-text-muted);
  text-align: center;
}

/* ===== 分割线 ===== */
.markdown-content :deep(hr) {
  border: none;
  height: 1px;
  background: var(--md-border);
  margin: 36px 0;
}

/* ===== 自定义容器（统一结构：左侧强调线 + 极浅底色 + 标题） ===== */
.markdown-content :deep(.custom-block) {
  margin: var(--md-space-lg) 0;
  padding: 14px 18px;
  border-radius: 0 var(--md-radius-md) var(--md-radius-md) 0;
  border-left: 3px solid var(--accent, var(--md-accent));
  background: var(--accent-bg, var(--md-tint));
}
.markdown-content :deep(.custom-block-title) {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 6px;
  font-size: 14px;
  font-weight: 700;
  color: var(--accent, var(--md-accent));
}
.markdown-content :deep(.custom-block > p) {
  margin-bottom: 8px;
  color: var(--md-text);
}
.markdown-content :deep(.custom-block > p:last-child) {
  margin-bottom: 0;
}
/* 各语义类型仅通过强调色区分，结构完全统一 */
.markdown-content :deep(.tip)     { --accent: var(--color-accent); --accent-bg: var(--color-accent-soft); }
.markdown-content :deep(.note)     { --accent: var(--color-progress); --accent-bg: var(--color-progress-soft); }
.markdown-content :deep(.warning)  { --accent: var(--color-warning); --accent-bg: var(--color-warning-soft); }
.markdown-content :deep(.danger)   { --accent: var(--color-danger); --accent-bg: var(--color-danger-soft); }
.markdown-content :deep(.example)  { --accent: #8B5CF6; --accent-bg: #F5F3FF; }
.markdown-content :deep(.success)  { --accent: var(--color-signal); --accent-bg: var(--color-signal-soft); }
/* example 为分类色（非状态），沿用独立色板 */
:global(html.dark) .markdown-content :deep(.example){ --accent: #A78BFA; --accent-bg: #2E1065; }
:global(html.dark) .markdown-content :deep(.success){ --accent: #4ADE80; --accent-bg: #052E16; }

/* ===== 折叠块 / 详情块（紧凑标题行 + 展开动画） ===== */
.markdown-content :deep(details) {
  margin: var(--md-space-md) 0;
  border: 1px solid var(--md-border);
  border-radius: var(--md-radius-md);
  padding: 0 16px;
  background: var(--md-tint);
}
.markdown-content :deep(summary) {
  cursor: pointer;
  padding: 12px 0;
  font-weight: 600;
  color: var(--md-text-strong);
  list-style: none;
  display: flex;
  align-items: center;
  gap: 8px;
  user-select: none;
}
.markdown-content :deep(summary)::-webkit-details-marker { display: none; }
.markdown-content :deep(summary)::before {
  content: "";
  width: 0;
  height: 0;
  border-left: 5px solid currentColor;
  border-top: 4px solid transparent;
  border-bottom: 4px solid transparent;
  transition: transform 0.15s ease;
  flex-shrink: 0;
}
.markdown-content :deep(details[open] > summary)::before {
  transform: rotate(90deg);
}
.markdown-content :deep(details > *:not(summary)) {
  padding-bottom: 14px;
}

/* ===== Mermaid / 图表（强独立内容：中性容器 + 横向滚动） ===== */
.markdown-content :deep(.mermaid) {
  margin: var(--md-space-lg) 0;
  padding: 20px;
  background: var(--md-tint);
  border: 1px solid var(--md-border-soft);
  border-radius: var(--md-radius-lg);
  overflow-x: auto;
  text-align: center;
  scrollbar-width: thin;
}
.markdown-content :deep(.mermaid svg) {
  max-width: 100%;
  height: auto;
  margin: 0 auto;
}

/* ===== 公式（块级：轻容器 + 横向滚动；行内：融入正文） ===== */
.markdown-content :deep(.katex-display),
.markdown-content :deep(.math-block) {
  margin: var(--md-space-lg) 0;
  padding: 16px 20px;
  background: var(--md-tint);
  border: 1px solid var(--md-border-soft);
  border-radius: var(--md-radius-md);
  overflow-x: auto;
  overflow-y: hidden;
  text-align: center;
  scrollbar-width: thin;
  cursor: zoom-in;
}
.markdown-content :deep(.katex-display > .katex) {
  font-size: 1.15em;
}
.markdown-content :deep(.katex) {
  color: var(--md-text);
  font-size: 1.05em;
}
/* 行内公式：与正文基线一致，不另起样式 */
.markdown-content :deep(.katex-error) {
  color: var(--color-danger-text);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}

/* ===== 任务列表 ===== */
.markdown-content :deep(.task-list-item) {
  list-style: none;
  position: relative;
  padding-left: 4px;
}
.markdown-content :deep(.task-list-item input) {
  margin-right: 8px;
  accent-color: var(--md-accent);
}
.markdown-content :deep(.task-list-item.task-list-item-checked) {
  color: var(--md-text-muted);
  text-decoration: line-through;
}

/* ===== 脚注 ===== */
.markdown-content :deep(.footnotes) {
  margin-top: 36px;
  padding-top: 24px;
  border-top: 1px solid var(--md-border);
  font-size: 13px;
}

/* ===== 移动端适配 ===== */
@media (max-width: 1024px) {
  .learn-reader-layout {
    flex-direction: column;
    gap: 0;
  }

  .learn-reader-main.has-toc,
  .learn-reader-main.no-toc {
    flex: none;
    max-width: 100%;
    width: 100%;
  }

  .learn-reader-toc {
    position: static;
    width: 100%;
    flex: none;
    max-height: none;
    order: -1;
    margin-bottom: 24px;
  }
}
</style>

<style>
/* ===== 全局 Markdown 文章样式（非 scoped，确保渲染内容生效） ===== */
html:not(.dark) .markdown-article {
  color: var(--color-foreground);
}

html.dark .markdown-article {
  color: var(--color-foreground);
}

html:not(.dark) .markdown-article .markdown-content :is(p, li, blockquote, td, th, dd, dt, figcaption, span),
html:not(.dark) .markdown-article header,
html:not(.dark) .markdown-article header time,
html:not(.dark) .markdown-article header span {
  color: var(--color-foreground);
}

html.dark .markdown-article .markdown-content :is(p, li, blockquote, td, th, dd, dt, figcaption, span),
html.dark .markdown-article header,
html.dark .markdown-article header time,
html.dark .markdown-article header span {
  color: var(--color-foreground);
}

html:not(.dark) .markdown-article .markdown-content :is(h1, h2, h3, h4, h5, h6) {
  color: var(--color-foreground);
}

html.dark .markdown-article .markdown-content :is(h1, h2, h3, h4, h5, h6) {
  color: var(--color-foreground);
}

html:not(.dark) .markdown-article .markdown-content :is(a, a:visited) {
  color: var(--color-accent-text);
}

html.dark .markdown-article .markdown-content :is(a, a:visited) {
  color: var(--color-accent-text);
}

html:not(.dark) .markdown-article .markdown-content :is(code):not(pre code):not(.code-block-wrapper code) {
  color: var(--color-accent-text);
}

html.dark .markdown-article .markdown-content :is(code):not(pre code):not(.code-block-wrapper code) {
  color: var(--color-accent-text);
}

/* Prism token 色彩覆盖 - 亮色主题 */
html:not(.dark) .token.comment,
html:not(.dark) .token.prolog,
html:not(.dark) .token.doctype,
html:not(.dark) .token.cdata {
  color: var(--color-muted-foreground) !important;
}

html:not(.dark) .token.punctuation {
  color: var(--color-muted-foreground) !important;
}

html:not(.dark) .token.property,
html:not(.dark) .token.tag,
html:not(.dark) .token.boolean,
html:not(.dark) .token.number,
html:not(.dark) .token.constant,
html:not(.dark) .token.symbol,
html:not(.dark) .token.deleted {
  color: #ea580c !important;
}

html:not(.dark) .token.selector,
html:not(.dark) .token.attr-name,
html:not(.dark) .token.string,
html:not(.dark) .token.char,
html:not(.dark) .token.builtin,
html:not(.dark) .token.inserted {
  color: var(--color-signal-text) !important;
}

html:not(.dark) .token.operator,
html:not(.dark) .token.entity,
html:not(.dark) .token.url {
  color: var(--color-foreground) !important;
}

html:not(.dark) .token.atrule,
html:not(.dark) .token.attr-value,
html:not(.dark) .token.keyword {
  color: #7c3aed !important;
}

html:not(.dark) .token.function,
html:not(.dark) .token.class-name {
  color: var(--color-accent-text) !important;
}

html:not(.dark) .token.regex,
html:not(.dark) .token.important,
html:not(.dark) .token.variable {
  color: var(--color-warning-text) !important;
}

/* Prism token 色彩覆盖 - 暗色主题 */
html.dark .token.comment,
html.dark .token.prolog,
html.dark .token.doctype,
html.dark .token.cdata {
  color: var(--color-muted-foreground) !important;
}

html.dark .token.punctuation {
  color: var(--color-muted-foreground) !important;
}

html.dark .token.property,
html.dark .token.tag,
html.dark .token.boolean,
html.dark .token.number,
html.dark .token.constant,
html.dark .token.symbol,
html.dark .token.deleted {
  color: var(--color-warning-text) !important;
}

html.dark .token.selector,
html.dark .token.attr-name,
html.dark .token.string,
html.dark .token.char,
html.dark .token.builtin,
html.dark .token.inserted {
  color: var(--color-signal-text) !important;
}

html.dark .token.operator,
html.dark .token.entity,
html.dark .token.url {
  color: var(--color-foreground) !important;
}

html.dark .token.atrule,
html.dark .token.attr-value,
html.dark .token.keyword {
  color: #a78bfa !important;
}

html.dark .token.function,
html.dark .token.class-name {
  color: var(--color-accent-text) !important;
}

html.dark .token.regex,
html.dark .token.important,
html.dark .token.variable {
  color: var(--color-warning-text) !important;
}

/* 暗色主题代码块背景 */
html.dark .markdown-content pre[class*='language-'],
html.dark .markdown-content code[class*='language-'] {
  background: var(--color-background) !important;
  color: var(--color-foreground) !important;
}

html:not(.dark) .markdown-content pre[class*='language-'],
html:not(.dark) .markdown-content code[class*='language-'] {
  background: var(--color-surface-muted) !important;
  color: var(--color-foreground) !important;
}
</style>
