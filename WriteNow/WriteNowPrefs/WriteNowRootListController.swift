import Combine
import SwiftUI
import SwiftUIIntrospect
import UIKit

final class WriteNowRootController: UIHostingController<WriteNowRootView> {
    private let primaryScrollViewSubject = CurrentValueSubject<UIScrollView?, Never>(nil)
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(rootView: WriteNowRootView(scrollViewSubject: primaryScrollViewSubject))

        primaryScrollViewSubject
            .compactMap { $0 }
            .sink { scrollView in
                NSLog("[WriteNow] Primary scroll view: \(scrollView)")
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc var contentScrollView: UIScrollView? {
        primaryScrollViewSubject.value
    }
}

@objc(WriteNowRootListController)
final class WriteNowRootListController: PSListController {
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("Write Now", bundle: Bundle.wrti_support, comment: "")
        navigationItem.largeTitleDisplayMode = .never

        let controller = WriteNowRootController()
        addChild(controller)

        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(controller.view)

        controller.didMove(toParent: self)
    }

    @objc var contentScrollView: UIScrollView? {
        (children.first as? WriteNowRootController)?.contentScrollView
    }
}
