import UIKit

/// 子页面都自己画「返回」并隐藏系统导航栏；UIKit 在导航栏隐藏时会停用左边缘右滑返回。
/// 这里把手势重新接上：只要栈里还有上一页，就允许从左边缘右滑返回。
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === interactivePopGestureRecognizer ? viewControllers.count > 1 : true
    }
}
