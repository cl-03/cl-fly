(function initChatCopy(global) {
  const ChatCopy = {
    agent: {
      queueIdle: '发送队列: 空闲',
      queuePaused: '发送队列: 自动重试已暂停',
      queueFailedPaused: function queueFailedPaused(count) { return '发送队列: ' + count + ' 条失败(自动重试暂停)'; },
      queueFailedPending: function queueFailedPending(count) { return '发送队列: ' + count + ' 条失败待重试'; },
      queueSending: function queueSending(count) { return '发送队列: 发送中 ' + count; },
      sendingAttempt: function sendingAttempt(attempt) { return '发送中... 第' + attempt + '次'; },
      failedWithRetry: function failedWithRetry(retries, reason, retryTip) { return '发送失败(已重试' + retries + '次): ' + reason + retryTip; },
      sent: '发送成功',
      retryOne: '重试此条',
      pauseAutoRetry: '暂停自动重试',
      resumeAutoRetry: '恢复自动重试',
      autoRetryEta: function autoRetryEta(sec) { return '，' + sec + 's后自动重试'; },
      autoRetryNow: '，可立即重试',
      exportRetryCsvDone: function exportRetryCsvDone(count) { return '已导出发送重试统计CSV（' + count + '条）'; },
      sendOkMeta: function sendOkMeta(sid) { return '发送成功 | sessionId=' + sid; },
      sendFailMeta: '发送失败，已加入发送队列',
      pausedMeta: '已暂停自动重试，仍可手动重试。',
      resumedMeta: '已恢复自动重试。'
    },
    visitor: {
      queueIdle: '发送队列: 空闲',
      queueFailed: function queueFailed(count) { return '发送队列: ' + count + ' 条失败'; },
      queueQueued: function queueQueued(count) { return '发送队列: ' + count + ' 条待发送'; },
      pendingFailed: '发送失败，等待自动重试',
      pendingSending: '发送中...',
      sendOkMeta: function sendOkMeta(sid) { return '发送成功 | sessionId=' + sid; },
      sendFailMeta: '发送失败，已进入离线保护发送队列',
      onlineMeta: '网络已恢复，正在自动重试发送队列消息',
      offlineMeta: '当前离线，已切换离线保护并暂存发送队列',
      offlineHint: '离线保护已启用：消息会暂存到本地发送队列并在恢复后自动重试。'
    }
  };

  global.ChatCopy = ChatCopy;
})(window);
