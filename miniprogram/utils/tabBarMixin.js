export default {
  data() {
    return {
      // 全局维护当前页面状态，使用getApp()确保状态不丢失
      globalTabState: getApp().globalData.tabState || {
        currentPage: 'index'
      }
    }
  },
  onLoad() {
    // 页面加载时更新当前页面标识
    const pagePath = this.$mp.page.route
    let currentPage = 'index'
    
    switch(pagePath) {
      case 'pages/saoma/saoma':
        currentPage = 'index'
        break
      case 'pages/home-page/page':
        currentPage = 'order'
        break
      case 'packageOther/ai-order-chat/ai-order-chat':
        currentPage = 'ai'
        break
      case 'pages/myorder/myorder':
        currentPage = 'myorder'
        break
      case 'pages/my/my':
        currentPage = 'my'
        break	
    }
    
    this.globalTabState.currentPage = currentPage
    getApp().globalData.tabState = this.globalTabState
  },
  methods: {
    handleTabChange(url) {
      // 使用switchTab确保页面不被销毁，而是切换显示
      uni.switchTab({
        url: url
      })
    }
  }
}
    