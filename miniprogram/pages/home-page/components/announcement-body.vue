<template>
  <view class="announcement-body-root">
    <rich-text class="announcement-item-html" :nodes="richHtml"></rich-text>
  </view>
</template>

<script>
import { getAnnouncementRichTextHtml } from "../../../utils/announcementContentParse.js";

export default {
  name: "AnnouncementBody",
  props: {
    /** 后端富文本：HTML 字符串；纯文本也会自动包一层排版 */
    content: {
      type: [String, Object],
      default: "",
    },
  },
  computed: {
    richHtml() {
      return getAnnouncementRichTextHtml(this.content);
    },
  },
};
</script>

<style scoped>
.announcement-body-root {
  width: 100%;
  overflow: hidden;
  padding: 4rpx 0;
  box-sizing: border-box;
}
.announcement-item-html {
  display: block;
  font-size: 28rpx;
  line-height: 1.75;
  color: #444;
}
</style>
