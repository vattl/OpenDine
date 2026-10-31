<template>
<!-- 单个商品弹出 - 使用一个根元素包裹所有内容 -->
<view class="popup-container">
	
    <!-- 遮罩层 -->
    <view class="details-back" @click="cLose()"></view>
	<view class="popup-wrapper">
	
    <scroll-view
      class="goods-details-scroll" 
      :scroll-y="true"   
      :enhanced="true" 
      :show-scrollbar="false"
      :scroll-with-animation="true" 
    >
		<!-- 弹窗内容 -->
		<view class="goods-details" @click.stop>
			<view class="goods-image">
				<!-- 使用 getBaseUrl() 拼完整地址，避免 baseUrl 未就绪时相对路径被解析到本地 -->
				<image 
					:src="dishImageSrc" 
					mode="widthFix" 
					class="square-image"
					lazy-load
				></image>
				<image :src="staticUrl('tab/guanbi.png')" mode="widthFix" @click="cLose" class="close-btn"></image>
			</view>
			<!-- 其他内容保持不变 -->
			<view 
				class="details-padd" 
				
			>
				<view class="name-container">
					<view class="details-name">{{ pro_details.itemgood.name }}</view>
					<view class="details-Thinning">已售 {{ pro_details.itemgood.monthlysale }}</view>
				</view>
				
				<!-- 规格选择 -->
				<view v-if = "pro_details.itemgood.specification != ''" class="specification-section">
					<view  v-for="(item,index) in specification" :key="index">
						<view class="spec-title">{{index}}</view>
						<view class="spec-options">
							<view 
								v-for="(itemthod,itemthod_index) in item" :key="itemthod_index"
								:class="['spec-option', selectedSpicy[index] === itemthod ? 'spec-selected' : '']"
								@click="onPickSpec(index, itemthod)"
							>
								{{itemthod}}
							</view>
						</view>
					</view>
				</view>	
						
			</view>
		</view>
	</scroll-view>
	<view  class="main-describe">
		<view class="describe">
			<view class="details-unit-price">
				<text class="details-unit-symbol">¥</text>
				<text class="details-unit-num">{{ pro_details.itemgood.unitprice }}</text>
				<text class="details-unit-unit">/{{ pro_details.itemgood.unit }}</text>
			</view>
			<view class="details-quantity">
				<view>
					<image 
						v-if="displayedQuantity > 0" 
						:src="staticUrl('tab/jianhao.png')" 
						@click.stop="reduce" 
						class="control-btn"
					></image>
				</view>
				<view><text  v-if="displayedQuantity > 0" >{{ displayedQuantity }}</text></view>
				<view>
					<image 
						:src="staticUrl('tab/jia.png')" 
						@click.stop="plus" 
						class="control-btn"
					></image>
				</view>
			</view>
			
		</view>
		<!-- 加入购物车按钮 -->
		<view class="add-to-cart-container">
			<button 
				class="add-to-cart-btn" 
				:class="{ 'add-to-cart-btn--soldout': !itemCanPurchase() }"
				@click="handleAddToCart"
				:disabled="!itemCanPurchase()"
			>
				{{ addCartBtnText }}
			</button>
		</view>	
	</view>		
	</view>	
</view>
</template>

<script>
import { getBaseUrl } from "../../../utils/requestUtil.js";
import { staticUrl } from "../../../utils/staticAssetUrl.js";
import { dishImageUrlOrDefault } from "../../../utils/imageUrl.js";
import { dishCanOrder, dishOnShelf, dishSoldOut } from "../../../utils/dishSale.js";
export default {
	data() {
		return {
			baseUrl: '',
			localQuantity: 1,
			selectedSpicy: '',
			specification:null
		};
	},
	
	props: {
		pro_details: {
			type: Object,
			default: () => ({})			
		},
		/** 与点餐页 POST /order/Business、WS business_changed 一致：true 表示当前非营业 */
		isNonBusinessHours: {
			type: Boolean,
			default: false,
		},
	},
	
	computed: {
		displayedQuantity() {
			return this.localQuantity;
		},
		dishImageSrc() {
			const img = this.pro_details && this.pro_details.itemgood && this.pro_details.itemgood.image;
			return dishImageUrlOrDefault(img, 'detail');
		},
		addCartBtnSoldOut() {
			return dishSoldOut(this.pro_details && this.pro_details.itemgood);
		},
		addCartBtnText() {
			if (this.isNonBusinessHours) return '非营业时间';
			if (this.addCartBtnSoldOut) return '已售罄';
			return '加入购物车';
		},
	},
	
	watch: {
		'pro_details.itemgood.new_quantity': {
			handler(newVal) {
				console.log(this.pro_details.new_quantity);
				this.localQuantity = newVal;
			},
			immediate: true,
			deep: true
		}
	},
	
	methods: {
		staticUrl,
		itemCanPurchase() {
			if (this.isNonBusinessHours) return false;
			return dishCanOrder(this.pro_details && this.pro_details.itemgood);
		},
		itemOnShelf() {
			return dishOnShelf(this.pro_details && this.pro_details.itemgood);
		},
		toastOffSale() {
			wx.showToast({ title: '该商品已下架', icon: 'none' });
		},
		toastSoldOut() {
			wx.showToast({ title: '该商品已售罄', icon: 'none' });
		},
		guardPurchase() {
			if (this.isNonBusinessHours) {
				wx.showToast({ title: '非营业时间', icon: 'none' });
				return false;
			}
			const g = this.pro_details && this.pro_details.itemgood;
			if (!dishOnShelf(g)) {
				this.toastOffSale();
				return false;
			}
			if (dishSoldOut(g)) {
				this.toastSoldOut();
				return false;
			}
			return true;
		},
		onPickSpec(groupKey, val) {
			if (!this.guardPurchase()) {
				return;
			}
			this.$set(this.selectedSpicy, groupKey, val);
		},
		spiceData(data){
			if(!data){
				return;
			}
			let spiceData = null;
			if (typeof data === 'object') {
				spiceData = data;
			} else if (typeof data === 'string') {
				try {
					spiceData = JSON.parse(data);
				} catch (e) {
					spiceData = { '口味': [data] };
				}
			}
			if (!spiceData || typeof spiceData !== 'object') return;
			this.specification = spiceData;
			
			/// 初始化每个规格的默认选中值
			const defaultSelected = {};
			Object.keys(spiceData).forEach(type => {
				const options = Array.isArray(spiceData[type]) ? spiceData[type] : [spiceData[type]];
				if (options.length >= 2) {
					defaultSelected[type] = options[1];
				} else if (options.length === 1) {
					defaultSelected[type] = options[0];
				} else {
					defaultSelected[type] = '';
				}
			});
			this.selectedSpicy = defaultSelected;
		},
		cLose() {
			this.$emit('close-popup');
		},
		
		reduce() {
			if (!this.guardPurchase()) {
				return;
			}
			if (this.localQuantity <= 0) return;
			const {index = 0, good_index = 0, cid = '', itemgood = {}} = this.pro_details;
			this.localQuantity = this.pro_details.itemgood.new_quantity - 1;
			
			this.$set(this.pro_details.itemgood, 'new_quantity', this.localQuantity);
		},
		
		plus() {
			if (!this.guardPurchase()) {
				return;
			}
			const {index = 0, good_index = 0, cid = '', itemgood = {}} = this.pro_details;
			
			this.localQuantity = this.pro_details.itemgood.new_quantity + 1;
			
			this.$set(this.pro_details.itemgood, 'new_quantity', this.localQuantity);
			console.log(this.pro_details);	
		},

		handleAddToCart() {
			if (!this.guardPurchase()) {
				return;
			}
			if (this.localQuantity <= 0) {
				wx.showToast({
					title: '请选择购买数量',
					icon: 'none'
				});
				return;
			}
			const {index = 0, good_index = 0, cid = '', itemgood = {}} = this.pro_details;
			this.pro_details.itemgood.quantity += this.pro_details.itemgood.new_quantity;
			console.log(this.pro_details);	
			
			this.$parent.plus(index, good_index, cid, {
				...itemgood,
				selectedSpicy: JSON.stringify(this.selectedSpicy,),
				new_quantity:this.localQuantity
			});
			
			this.cLose();
			
			wx.showToast({
				title: '已加入购物车',
				icon: 'success',
				duration: 1500
			});
		}
	},
	
	created() {
		this.baseUrl = getBaseUrl();
		console.log(this.baseUrl);
		this.spiceData(this.pro_details.itemgood.specification);
		
	}
};
</script>

<style scoped>
.popup-wrapper{
    position: absolute;
	height: 400px;
    bottom: 210rpx;
    left: 0;
    right: 0;
    /* 固定高度 - 可以根据需求调整，这里设置为屏幕高度的80% */
    /* 或者使用固定rpx值：height: 800rpx; */
	z-index:998;
}
.goods-details-scroll {
  width: 100%;
  height: 100%;
  -webkit-overflow-scrolling: touch;
  touch-action: pan-y; /* 明确只允许垂直滚动 */
  /* 新增：禁止滚动容器抖动 */
  will-change: scroll-position;
  backface-visibility: hidden;
  
}	
/* 根容器样式 */
.popup-container {
    position: relative;
}

.details-back {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: rgba(0, 0, 0, 0.6);
    z-index: 998;
}

.goods-details {
	position: inherit;
    bottom: 0;
    left: 0;
    right: 0;
    background-color: #fff;
    border-top-left-radius: 30rpx;
    border-top-right-radius: 30rpx;
}

/* 正方形图片容器和图片样式 */
.goods-image {
    width: 100%;
    /* 关键：设置容器为正方形（宽高比1:1） */
    aspect-ratio: 3 / 2;
    position: relative;
    overflow: hidden;
	background: transparent;
}

.square-image {
    /* 图片宽度充满容器 */
    width: 100%;
    /* 高度自动适应，保持比例 */
    height: 80vh;
    /* 确保图片居中显示 */
    object-fit: cover;
    border-top-left-radius: 20rpx;
    border-top-right-radius: 20rpx;
}

/* 关闭按钮样式（组件 wxss 不允许标签选择器，用类选择器） */
.goods-image .close-btn {
	width: 50rpx;
	height: 50rpx;
	position: absolute;
	top: 20rpx;
	right: 20rpx;
	border-radius: 50%;
	z-index: 10;
}

.details-padd {
    padding: 20rpx 20rpx 180rpx 20rpx;
	background-color: white;
	top: 260px;
}
.main-describe {
	background-color: white;
	padding: 0 20rpx 20rpx 20rpx;
}
.describe {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 30rpx;
}

.details-quantity .control-btn {
    width: 50rpx;
    height: 50rpx;
    display: block;
}

.details-quantity {
    display: flex;
    align-items: center;
    width: 200rpx;
    justify-content: space-between;
}

.control-btn {
    padding: 10rpx;
    margin: -10rpx;
    transition: transform 0.1s ease;
}

.control-btn:active {
    transform: scale(0.9);
}

.name-container {
    display: flex;
    align-items: center;
    gap: 15rpx;
    margin-bottom: 20rpx;
}

.details-name {
    font-size: 35rpx;
    font-weight: bold;
    flex: 1;
    word-break: break-all;
}

.details-Thinning {
    font-size: 30rpx;
    color: #a4a4a4;
    padding: 0;
    white-space: nowrap;
}

.details-unit-price {
    font-size: 30rpx;
    color: #ec0606;
    display: flex;
    align-items: baseline;
}

.details-unit-price .details-unit-num {
    font-size: 35rpx;
}

.details-unit-price .details-unit-unit {
    color: #999999 !important;
}

.close-btn {
    background: transparent;
    border: none;
    padding: 0;
}

.specification-section {
    margin: 10rpx 0 30rpx 0;
}

.spec-title {
    font-size: 25rpx;
    color: #333;
    margin-bottom: 15rpx;
}

.spec-options {
    display: flex;
    gap: 20rpx;
}

.spec-option {
    padding: 15rpx 30rpx;
    border: 2rpx solid #ddd;
    border-radius: 10rpx;
    font-size: 30rpx;
    cursor: pointer;
    transition: all 0.2s ease;
}

.spec-selected {
    border-color: #ec0606;
    background-color: rgba(236, 112, 45, 0.1);
    color: #ec0606;
}

.add-to-cart-container {
    padding: 20rpx 0 30rpx 0;
	z-index:999;
}

.add-to-cart-btn {
    width: 100%;
    height: 100rpx;
    line-height: 100rpx;
    background:linear-gradient(to right,#ff5117,#f0331a,#e10606,#d30606);
    color: #fff;
    font-size: 32rpx;
    font-weight: bold;
    border-radius: 50rpx;
    border: none;
}

.add-to-cart-btn::after {
    border: none;
}

.add-to-cart-btn:disabled {
    background-color: #ccc;
    color: #666;
}

/* sold_out=1：灰色不可点（覆盖渐变） */
.add-to-cart-btn--soldout,
.add-to-cart-btn--soldout:disabled {
	background: #e5e5e5 !important;
	background-image: none !important;
	color: #999 !important;
}
</style>
