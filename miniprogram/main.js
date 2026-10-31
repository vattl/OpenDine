import App from './App'
import Vue from 'vue'
import GlobalActivityPopup from './components/GlobalActivityPopup.vue'
import globalActivityPopupMixin from './utils/globalActivityPopupMixin.js'

// css3动画样式
import './style/animat.css'

Vue.component('global-activity-popup', GlobalActivityPopup)
Vue.mixin(globalActivityPopupMixin)
Vue.config.productionTip = false
App.mpType = 'app'
const app = new Vue({
    ...App
	
})
app.$mount()
