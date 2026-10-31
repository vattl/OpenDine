<template>
<!-- 弹出购物车 -->
<view>
	<view class="details-back" @click="cLose()"></view>
	<view class="goods-details coup-anim cart-popup-root">
		<view class="empty cart-popup-header">
			<image class="empty-icon" :src="staticUrl('tab/qingkong.svg')" mode="widthFix"></image>
			<text class="empty-text" @click="empTy()">清空已点</text>
		</view>
		<scroll-view class="cart-popup-scroll" scroll-y :enable-flex="true" :show-scrollbar="false">
			<block v-for="(item,index) in shopping_card" :key="index">
				<view class="goods-list" v-if="item.quantity > 0">
					<view class="goods-list-image"><image class="goods-list-img" :src="dishImageUrlOrDefault(item.image, 'list')" mode="aspectFill" lazy-load></image></view>
					<view class="goods-list-name">
						<view class="product-name">
							<text class="product-name-text">{{ item.name }}</text>
						</view>
						<view
							class="spicy-tag"
							v-if="getSpicyText(item.selectedSpicy)"
						>{{ getSpicyText(item.selectedSpicy) }}</view>
						<view class="list-text">
							<text class="list-text-symbol">¥</text>
							<text class="list-text-price">{{item.total_price}}</text>
						</view>
					</view>
					<view class="goods-quantity">
						<view><image class="quantity-icon" :src="staticUrl('tab/jianhao.png')" mode="widthFix" @click="reduce(index,item.quantity,item.id || item._id,item.cid,item.good_index,item.unitprice)"></image></view>
						<view>{{item.quantity}}</view>
						<view><image class="quantity-icon" :src="staticUrl('tab/jia.png')" mode="widthFix" @click="plus(index,item.quantity,item.id || item._id,item.cid,item.good_index,item.unitprice)"></image></view>
					</view>
				</view>
			</block>
			<view class="cart-popup-scroll-pad"></view>
		</scroll-view>
	</view>
</view>
</template>

<script>
import { staticUrl } from "../../../utils/staticAssetUrl.js";
import { dishImageUrlOrDefault } from "../../../utils/imageUrl.js";
export default{
	data() {
		return{
			baseUrl:''
		}
	},
	props:{
		shopping_card:Array
	},
	methods:{
		staticUrl,
		dishImageUrlOrDefault,
		cLose(){
			// 调用父组件的pop_Shopping()
			this.$parent.pop_Shopping(false)
		},
		// -
		reduce(index,quantity,_id,cid,good_index,unitprice){
			const QU = quantity - 1
			this.$parent.shopping_Cart_add_sub(index,QU*-1,_id,cid,good_index,unitprice)
		},
		// +
		plus(index,quantity,_id,cid,good_index,unitprice){
			const QU = quantity + 1
			this.$parent.shopping_Cart_add_sub(index,QU,_id,cid,good_index,unitprice)
		},
		// 清空已点
		empTy(){
			this.$parent.empty_data()
		},
		/** 辣度展示：首页为 JSON 字符串；AI 加购等可能为纯文本（如「不辣」），不可直接 JSON.parse */
		getSpicyText(spicy) {
			if (spicy == null || spicy === '') return '';
			if (typeof spicy === 'object' && spicy !== null && !Array.isArray(spicy)) {
				const result = Object.entries(spicy)
					.map(([, value]) => `${value}`)
					.join(',');
				return result || '';
			}
			const s = String(spicy).trim();
			if (!s || s === '{}') return '';
			try {
				const parsed = JSON.parse(s);
				if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
					return Object.entries(parsed)
						.map(([, value]) => `${value}`)
						.join(',');
				}
				return typeof parsed === 'string' ? parsed : s;
			} catch (e) {
				return s;
			}
		}
	}
}
</script>

<style scoped>
@import '../../../style/shadow.css';
/* 组件 wxss 不允许标签选择器，使用类选择器 */
.empty-icon{
	width: 25rpx;
	height: 25rpx;
	display: block;
	padding-right: 10rpx;
}
/* 弹层整体：顶栏固定，仅下方列表滚动（覆盖 shadow.css 里整块 overflow-y） */
.cart-popup-root.goods-details {
	display: flex;
	flex-direction: column;
	overflow: hidden;
	box-sizing: border-box;
}
.cart-popup-header.empty {
	flex-shrink: 0;
	background-color: #fefefe;
	z-index: 2;
}
.empty{
	font-size: 25rpx;
	color: #aaaaaa;
	height: 90rpx;
	border-bottom: 1rpx solid #f2f2f2;
	display: flex;
	align-items: center;
	justify-content: flex-end;
	margin: 0 20rpx;
}
.cart-popup-scroll {
	flex: 1;
	min-height: 0;
	height: calc(850rpx - 90rpx);
	box-sizing: border-box;
}
.cart-popup-scroll-pad {
	height: 100rpx;
}
.goods-list-img{
	display: block;
	width: 130rpx;
	height: 130rpx;
	border-radius: 10rpx;
}
.quantity-icon{
	display: block;
	width: 50rpx;
	height: 50rpx;
}
.goods-quantity{
	display: flex;
	align-items: center;
	align-self: flex-end;
	width: 200rpx;
	justify-content: space-between;
}
.goods-list{
	display: flex;
	justify-content: space-between;
	padding: 0 20rpx;
	height: 130rpx;
	font-size: 30rpx;
	margin: 25rpx 0 45rpx 0;
}
.details-back{
	z-index: 995;
}
.goods-details{
	z-index: 996;
}
.goods-list-name{
	flex: 1;
	min-width: 0;
	position: relative;
	padding: 0 20rpx;
	overflow: hidden;
}
.list-text-symbol,
.list-text-price{
	display: block;
}
.list-text{
	display: flex;
	align-items: center;
	position: absolute;
	bottom: 0;
}
.list-text-symbol{
	font-size: 25rpx;
	padding-right: 5rpx;
}

/* 辣度标签样式 */
.spicy-tag {
	font-size: 24rpx;
	color: #777;
	background-color: #f5f5f5;
	padding: 2rpx 15rpx;
	border-radius: 15rpx;
	display: inline-block;
	margin-top: 8rpx;
}

/* 商品名称样式调整 */
.product-name {
	display: flex;
	align-items: center;
	min-width: 0;
	font-weight: 500;
	line-height: 1.2;
}
.product-name-text {
	flex: 1;
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}
</style>
