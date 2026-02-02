// Cloudflare Worker - GitHub 代理
// 部署到 Cloudflare Workers 后，可用于加速 GitHub 访问

const GITHUB_HOST = 'github.com';
const RAW_HOST = 'raw.githubusercontent.com';

async function handleRequest(request) {
  const url = new URL(request.url);
  const path = url.pathname;

  // 根路径返回使用说明
  if (path === '/' || path === '') {
    return new Response(
      `GitHub Proxy\n\nUsage:\n  ${url.origin}/https://github.com/user/repo\n  ${url.origin}/https://raw.githubusercontent.com/user/repo/main/file`,
      { headers: { 'Content-Type': 'text/plain; charset=utf-8' } }
    );
  }

  // 解析目标 URL
  let targetUrl;
  if (path.startsWith('/https://')) {
    targetUrl = path.slice(1) + url.search;
  } else if (path.startsWith('/http://')) {
    targetUrl = path.slice(1).replace('http://', 'https://') + url.search;
  } else {
    // 默认代理 github.com
    targetUrl = `https://github.com${path}${url.search}`;
  }

  try {
    const targetUrlObj = new URL(targetUrl);

    // 只允许 GitHub 相关域名
    const allowedHosts = [
      'github.com',
      'raw.githubusercontent.com',
      'gist.githubusercontent.com',
      'codeload.github.com',
      'objects.githubusercontent.com',
      'api.github.com',
    ];

    if (!allowedHosts.some((host) => targetUrlObj.hostname === host || targetUrlObj.hostname.endsWith('.' + host))) {
      return new Response('Forbidden: Only GitHub domains are allowed', { status: 403 });
    }

    // 构建新请求
    const newRequest = new Request(targetUrl, {
      method: request.method,
      headers: request.headers,
      body: request.body,
      redirect: 'follow',
    });

    // 移除可能导致问题的头
    const headers = new Headers(newRequest.headers);
    headers.delete('host');

    const response = await fetch(targetUrl, {
      method: request.method,
      headers: headers,
      body: request.body,
      redirect: 'follow',
    });

    // 复制响应并修改头
    const newResponse = new Response(response.body, response);
    newResponse.headers.set('Access-Control-Allow-Origin', '*');
    newResponse.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    newResponse.headers.set('Access-Control-Allow-Headers', '*');

    return newResponse;
  } catch (error) {
    return new Response(`Error: ${error.message}`, { status: 500 });
  }
}

export default {
  async fetch(request) {
    // 处理 CORS 预检请求
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': '*',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    return handleRequest(request);
  },
};
